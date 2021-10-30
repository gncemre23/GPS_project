/******************************************************************************
 * Copyright (C) 2010 - 2020 Xilinx, Inc.  All rights reserved.
 * SPDX-License-Identifier: MIT
 ******************************************************************************/

/*****************************************************************************/
/**
 *
 * @file xaxidma_example_simple_intr.c
 *
 * This file demonstrates how to use the xaxidma driver on the Xilinx AXI
 * DMA core (AXIDMA) to transfer packets.in interrupt mode when the AXIDMA core
 * is configured in simple mode
 *
 * This code assumes a loopback hardware widget is connected to the AXI DMA
 * core for data packet loopback.
 *
 * To see the debug print, you need a Uart16550 or uartlite in your system,
 * and please set "-DDEBUG" in your compiler options. You need to rebuild your
 * software executable.
 *
 * Make sure that MEMORY_BASE is defined properly as per the HW system. The
 * h/w system built in Area mode has a maximum DDR memory limit of 64MB. In
 * throughput mode, it is 512MB.  These limits are need to ensured for
 * proper operation of this code.
 *
 *
 * <pre>
 * MODIFICATION HISTORY:
 *
 * Ver   Who  Date     Changes
 * ----- ---- -------- -------------------------------------------------------
 * 4.00a rkv  02/22/11 New example created for simple DMA, this example is for
 *       	       simple DMA,Added interrupt support for Zynq.
 * 4.00a srt  08/04/11 Changed a typo in the RxIntrHandler, changed
 *		       XAXIDMA_DMA_TO_DEVICE to XAXIDMA_DEVICE_TO_DMA
 * 5.00a srt  03/06/12 Added Flushing and Invalidation of Caches to fix CRs
 *		       648103, 648701.
 *		       Added V7 DDR Base Address to fix CR 649405.
 * 6.00a srt  03/27/12 Changed API calls to support MCDMA driver.
 * 7.00a srt  06/18/12 API calls are reverted back for backward compatibility.
 * 7.01a srt  11/02/12 Buffer sizes (Tx and Rx) are modified to meet maximum
 *		       DDR memory limit of the h/w system built with Area mode
 * 7.02a srt  03/01/13 Updated DDR base address for IPI designs (CR 703656).
 * 9.1   adk  01/07/16 Updated DDR base address for Ultrascale (CR 799532) and
 *		       removed the defines for S6/V6.
 * 9.2   vak  15/04/16 Fixed compilation warnings in the example
 * 9.3   ms   01/23/17 Modified xil_printf statement in main function to
 *                     ensure that "Successfully ran" and "Failed" strings are
 *                     available in all examples. This is a fix for CR-965028.
 * 9.6   rsp  02/14/18 Support data buffers above 4GB.Use UINTPTR for typecasting
 *                     buffer address (CR-992638).
 * 9.9   rsp  01/21/19 Fix use of #elif check in deriving DDR_BASE_ADDR.
 * 9.10  rsp  09/17/19 Fix cache maintenance ops for source and dest buffer.
 * 9.11  rsp  04/15/20 Fix s2mm "Engine is busy" failure for smaller(<16)
 *                     packet size.
 * </pre>
 *
 * ***************************************************************************
 */

/***************************** Include Files *********************************/

#include "xaxidma.h"
#include "xparameters.h"
#include "xil_exception.h"
#include "xdebug.h"
#include "xsdps.h"
#include "ff.h"
#include "xplatform_info.h"
#include "xil_printf.h"
#include "xil_cache.h"

#ifdef XPAR_UARTNS550_0_BASEADDR
#include "xuartns550_l.h" /* to use uartns550 */
#endif

#ifdef XPAR_INTC_0_DEVICE_ID
#include "xintc.h"
#else
#include "xscugic.h"
#endif

/************************** Constant Definitions *****************************/

/*
 * Device hardware build related constants.
 */

#define DMA_DEV_ID XPAR_AXIDMA_0_DEVICE_ID

#ifdef XPAR_AXI_7SDDR_0_S_AXI_BASEADDR
#define DDR_BASE_ADDR XPAR_AXI_7SDDR_0_S_AXI_BASEADDR
#elif defined(XPAR_MIG7SERIES_0_BASEADDR)
#define DDR_BASE_ADDR XPAR_MIG7SERIES_0_BASEADDR
#elif defined(XPAR_MIG_0_BASEADDR)
#define DDR_BASE_ADDR XPAR_MIG_0_BASEADDR
#elif defined(XPAR_PSU_DDR_0_S_AXI_BASEADDR)
#define DDR_BASE_ADDR XPAR_PSU_DDR_0_S_AXI_BASEADDR
#endif

#ifndef DDR_BASE_ADDR
//#warning CHECK FOR THE VALID DDR ADDRESS IN XPARAMETERS.H, DEFAULT SET TO 0x01000000
#define MEM_BASE_ADDR 0x01000000
#else
#define MEM_BASE_ADDR (DDR_BASE_ADDR + 0x1000000)
#endif

#ifdef XPAR_INTC_0_DEVICE_ID
#define RX_INTR_ID XPAR_INTC_0_AXIDMA_0_S2MM_INTROUT_VEC_ID
#define TX_INTR_ID XPAR_INTC_0_AXIDMA_0_MM2S_INTROUT_VEC_ID
#else
#define RX_INTR_ID XPAR_FABRIC_AXIDMA_0_S2MM_INTROUT_VEC_ID
#define TX_INTR_ID XPAR_FABRIC_AXIDMA_0_MM2S_INTROUT_VEC_ID
#endif

#define TX_BUFFER_BASE (MEM_BASE_ADDR + 0x00100000)
#define RX_BUFFER_BASE (MEM_BASE_ADDR + 0x01000000)
#define RX_BUFFER_HIGH (MEM_BASE_ADDR + 0x02FFFFFF)

#ifdef XPAR_INTC_0_DEVICE_ID
#define INTC_DEVICE_ID XPAR_INTC_0_DEVICE_ID
#else
#define INTC_DEVICE_ID XPAR_SCUGIC_SINGLE_DEVICE_ID
#endif

#ifdef XPAR_INTC_0_DEVICE_ID
#define INTC XIntc
#define INTC_HANDLER XIntc_InterruptHandler
#else
#define INTC XScuGic
#define INTC_HANDLER XScuGic_InterruptHandler
#endif

/* Timeout loop counter for reset
 */
#define RESET_TIMEOUT_COUNTER 10000

#define TEST_START_VALUE 0xC
/*
 * Buffer and Buffer Descriptor related constant definition
 */
#define MAX_PKT_LEN 0x100

#define NUMBER_OF_TRANSFERS 10

//FFT point size = 1024 and 64-bit of 80-bit is received for the simplicity
#define RX_SIZE 1024 * 8

/* The interrupt coalescing threshold and delay timer threshold
 * Valid range is 1 to 255
 *
 * We set the coalescing threshold to be the total number of packets.
 * The receive side will only get one completion interrupt for this example.
 */

/**************************** Type Definitions *******************************/

/***************** Macros (Inline Functions) Definitions *********************/

/************************** Function Prototypes ******************************/
#ifndef DEBUG
extern void xil_printf(const char *format, ...);
#endif

#ifdef XPAR_UARTNS550_0_BASEADDR
static void Uart550_Setup(void);
#endif

static void TxIntrHandler(void *Callback);
static void RxIntrHandler(void *Callback);

static int SetupIntrSystem(INTC *IntcInstancePtr, XAxiDma *AxiDmaPtr,
                           u16 TxIntrId, u16 RxIntrId);
static void DisableIntrSystem(INTC *IntcInstancePtr, u16 TxIntrId,
                              u16 RxIntrId);

/************************** Variable Definitions *****************************/
/*
 * Device instance definitions
 */

static XAxiDma AxiDma; /* Instance of the XAxiDma */

static INTC Intc; /* Instance of the Interrupt Controller */

static char InputFileName[32] = "test_in.bin";
static char OutputFileName[32] = "test_out.bin";
static char *SD_File_in;
static char *SD_File_out;

static FIL fil_in, fil_out; /* File object */
static FATFS fatfs;
/*
 * Flags interrupt handlers use to notify the application context the events.
 */
volatile int TxDone;
volatile int RxDone;
volatile int Error;

/*****************************************************************************/
/**
 *
 * Main function
 *
 * This function is the main entry of the interrupt test. It does the following:
 *	Set up the output terminal if UART16550 is in the hardware build
 *	Initialize the DMA engine
 *	Set up Tx and Rx channels
 *	Set up the interrupt system for the Tx and Rx interrupts
 *	Submit a transfer
 *	Wait for the transfer to finish
 *	Check transfer status
 *	Disable Tx and Rx interrupts
 *	Print test status and exit
 *
 * @param	None
 *
 * @return
 *		- XST_SUCCESS if example finishes successfully
 *		- XST_FAILURE if example fails.
 *
 * @note		None.
 *
 ******************************************************************************/
#define BUFLENGTH 1024

#define IF 14.5799999999999e6
// -- - Find 1 chip wide C / A code phase exclude range around the peak----
//double samplesPerCodeChip = round(settings->samplingFreq / settings->codeFreqBasis);
// for simplicty it consider as a constant
#define SAMPLEPERCODECHIP 53
//search from IF-10khz to IF+10kHz
#define SEARCH_BAND 20
//frequency resolution provided by dds compiler
#define FREQ_RES 381.46
int main(void)
{
    int Status;
    XAxiDma_Config *Config;
    u8 *TxBufferPtr;
    u8 *RxBufferPtr;
    //
    //	u8 TxBufferPtr[10 * 1024] __attribute__ ((aligned(32)));
    //	u8 RxBufferPtr[10 * 1024] __attribute__ ((aligned(32)));
    //u32 rx_size = 0;

    //BYTE work[FF_MAX_SS];

    //variables for SD File system
    FRESULT Res;
    UINT NumBytesRead;
    //UINT NumBytesWritten;

    /****************** SD Config ******************************/

    TCHAR *Path = "0:/";

    /*
	 * Register volume work area, initialize device
	 */
    Res = f_mount(&fatfs, Path, 0);
    if (Res != FR_OK)
    {
        return XST_FAILURE;
    }

    //	Res = f_mkfs(Path, FM_FAT32, 0, work, sizeof work);
    //	if (Res != FR_OK) {
    //		return XST_FAILURE;
    //	}

    /*
	 * Open file with required permissions.
	 * Here - Creating new file with read/write permissions. .
	 * To open file with write permissions, file system should not
	 * be in Read Only mode.
	 */
    SD_File_in = (char *)InputFileName;
    SD_File_out = (char *)OutputFileName;

    Res = f_open(&fil_in, SD_File_in, FA_READ);
    if (Res)
    {
        return XST_FAILURE;
    }

    Res = f_open(&fil_out, SD_File_out, FA_CREATE_ALWAYS | FA_WRITE);
    if (Res)
    {
        return XST_FAILURE;
    }

    /*
	 * Pointer to beginning of input file .
	 */
    Res = f_lseek(&fil_in, 0);
    if (Res)
    {
        return XST_FAILURE;
    }

    /*
	 * Pointer to beginning of output file .
	 */
    Res = f_lseek(&fil_out, 0);
    if (Res)
    {
        return XST_FAILURE;
    }

    /****************** SD Config ******************************/

    TxBufferPtr = (u8 *)TX_BUFFER_BASE;
    RxBufferPtr = (u8 *)RX_BUFFER_BASE;
    /* Initial setup for Uart16550 */
#ifdef XPAR_UARTNS550_0_BASEADDR

    Uart550_Setup();

#endif

    xil_printf("\r\n--- Entering main() --- \r\n");

    Config = XAxiDma_LookupConfig(DMA_DEV_ID);
    if (!Config)
    {
        xil_printf("No config found for %d\r\n", DMA_DEV_ID);

        return XST_FAILURE;
    }

    /* Initialize DMA engine */
    Status = XAxiDma_CfgInitialize(&AxiDma, Config);

    if (Status != XST_SUCCESS)
    {
        xil_printf("Initialization failed %d\r\n", Status);
        return XST_FAILURE;
    }

    if (XAxiDma_HasSg(&AxiDma))
    {
        xil_printf("Device configured as SG mode \r\n");
        return XST_FAILURE;
    }

    /* Set up Interrupt system  */
    Status = SetupIntrSystem(&Intc, &AxiDma, TX_INTR_ID, RX_INTR_ID);
    if (Status != XST_SUCCESS)
    {

        xil_printf("Failed intr setup\r\n");
        return XST_FAILURE;
    }

    /* Disable all interrupts before setup */

    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);

    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    /* Enable all interrupts */
    XAxiDma_IntrEnable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);

    XAxiDma_IntrEnable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    Xil_DCacheDisable();
    NumBytesRead = 8192;
    //rx_size = 8;
    int ms = 0;
    int PRN_index = 0;
    uint64_t acq_res[2][54][RX_SIZE / 8];
    uint64_t max0[54] = {0}, max1[54] = {0};
    uint32_t result[54][RX_SIZE / 8];
    uint32_t peaksize = 0;
    uint16_t codePhase = 0;
    int frequencyBinIndex = 0;
 //   double acq_result[32] = {0.0};
    xil_printf("PRN  | Acquisition Result |  Codephase | Carrier frequency \r\n");

    for (PRN_index = 0; PRN_index < 32; PRN_index++)
    {
        *((uint32_t *)(0x43C00000)) = PRN_index;
        for (ms = 0; ms < 2; ms++)
        {
            /* Initialize flags before start transfer test  */
            TxDone = 0;
            RxDone = 0;
            Error = 0;
            /*
			 * Read data from file to reserved DDR address for TX.
			 */
            Res = f_read(&fil_in, (void *)TxBufferPtr, BUFLENGTH, &NumBytesRead);
            if (Res)
            {
                return XST_FAILURE;
            }
//            xil_printf("reading byte:%x\r\n", *((uint32_t *)TxBufferPtr + (BUFLENGTH - 16) / 4));

            //sending the data read from SD to PL by AXIDMA
            Status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)TxBufferPtr, NumBytesRead, XAXIDMA_DMA_TO_DEVICE);
            if (Status != XST_SUCCESS)
            {
                return XST_FAILURE;
            }

            while (TxDone == 0)
                ;
//
            int ix = 0;
            for (size_t freq_bin = 0; freq_bin < 54; freq_bin++)
            {
            	RxDone = 0;
                Status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)RxBufferPtr, RX_SIZE, XAXIDMA_DEVICE_TO_DMA);

                if (Status != XST_SUCCESS)
                {
                    return XST_FAILURE;
                }

                while (RxDone == 0)
                    ;
                memcpy(acq_res[ms][freq_bin], RxBufferPtr, RX_SIZE);
                ix++;
            }

            /*
			 * Write data to file.
	//		 */
            //		Res = f_write(&fil_out, (const void*) RxBufferPtr, NumBytesRead, &NumBytesWritten);
            //		if (Res) {
            //			return XST_FAILURE;
            //		}
            //		xil_printf("writing byte:%d\r\n", NumBytesWritten);
        }


        //------------------------------ PEAK DETECTION-------------------------------------------


        for (size_t f = 0; f < 54; f++)
        {
        	max0[f] = 0;
        	max1[f] = 0;
            for (size_t i = 0; i < RX_SIZE / 8; i++)
            {
                if (acq_res[0][f][i] > max0[f])
                {
                    max0[f] = acq_res[0][f][i];
                }

                if (acq_res[1][f][i] > max1[f])
                {
                    max1[f] = acq_res[1][f][i];
                }
            }
        }

        //finding the freq_bins that has the max values and copy them to the result array.
        for (size_t f = 0; f < 54; f++)
        {
            if (max0[f] > max1[f])
                for (size_t i = 0; i < RX_SIZE / 8; i++)
                {
                    result[f][i] = acq_res[0][f][i];
                }
            else
                for (size_t i = 0; i < RX_SIZE / 8; i++)
                {
                    result[f][i] = acq_res[1][f][i];
                }
        }

        //Finding the peaksize and codephase
        peaksize = 0;
        for (size_t f = 0; f < 54; f++)
        {
            for (size_t i = 10; i < RX_SIZE / 8 - 10; i++)
            {
                if (result[f][i] > peaksize)
                {
                    peaksize = result[f][i];
                    codePhase = i;
                    frequencyBinIndex = f;
                }
            }
        }

//        uint64_t excludeRangeIndex1 = codePhase - SAMPLEPERCODECHIP;
//        uint64_t excludeRangeIndex2 = codePhase + SAMPLEPERCODECHIP;
//        int codePhaseRange[RX_SIZE / 8] = {0};
//        int newerCodeLen = 0;

//        if (excludeRangeIndex1 < 2)
//        {
//            for (size_t i = excludeRangeIndex2; i <= (RX_SIZE / 8 + excludeRangeIndex1); i++)
//            {
//                codePhaseRange[newerCodeLen] = i;
//                newerCodeLen++;
//            }
//        }
//        else if (excludeRangeIndex2 >= RX_SIZE / 8)
//        {
//            for (size_t i = (excludeRangeIndex2 - RX_SIZE / 8); i <= excludeRangeIndex1; i++)
//            {
//                codePhaseRange[newerCodeLen] = i;
//                newerCodeLen++;
//            }
//        }
//        else
//        {
//            for (size_t i = 0; i <= excludeRangeIndex1; i++)
//            {
//                codePhaseRange[newerCodeLen] = i;
//                newerCodeLen++;
//            }
//            for (size_t i = excludeRangeIndex2; i < RX_SIZE / 8; i++)
//            {
//                codePhaseRange[newerCodeLen] = i;
//                newerCodeLen++;
//            }
//        }
//
//        // Find the second highest correlation peak in the same freq.bin-- -
//        uint64_t secondPeakSize = 0;
//        for (size_t i = 0; i < newerCodeLen; i++)
//        {
//            if (secondPeakSize < result[frequencyBinIndex][codePhaseRange[i]])
//            {
//                secondPeakSize = result[frequencyBinIndex][codePhaseRange[i]];
//            }
//        }
        //acq_result[PRN_index] = (double)peaksize/(double)secondPeakSize;
        float carrier_freq = IF - SEARCH_BAND/2 + FREQ_RES * frequencyBinIndex;
        xil_printf("%d ", PRN_index+1);
        xil_printf("     %u", peaksize);
        xil_printf("                  %u", codePhase);
        printf("            %f \r\n", carrier_freq);
    }

    f_close(&fil_in);
    f_close(&fil_out);
    xil_printf("Successfully ran AXI DMA SD card to acquisition\r\n");

    /* Disable TX and RX Ring interrupts and return success */

    DisableIntrSystem(&Intc, TX_INTR_ID, RX_INTR_ID);

    return XST_SUCCESS;
}

#ifdef XPAR_UARTNS550_0_BASEADDR
/*****************************************************************************/
/*
 *
 * Uart16550 setup routine, need to set baudrate to 9600 and data bits to 8
 *
 * @param	None
 *
 * @return	None
 *
 * @note		None.
 *
 ******************************************************************************/
static void Uart550_Setup(void)
{

    XUartNs550_SetBaud(XPAR_UARTNS550_0_BASEADDR,
                       XPAR_XUARTNS550_CLOCK_HZ, 9600);

    XUartNs550_SetLineControlReg(XPAR_UARTNS550_0_BASEADDR,
                                 XUN_LCR_8_DATA_BITS);
}
#endif

/*****************************************************************************/
/*
 *
 * This is the DMA TX Interrupt handler function.
 *
 * It gets the interrupt status from the hardware, acknowledges it, and if any
 * error happens, it resets the hardware. Otherwise, if a completion interrupt
 * is present, then sets the TxDone.flag
 *
 * @param	Callback is a pointer to TX channel of the DMA engine.
 *
 * @return	None.
 *
 * @note		None.
 *
 ******************************************************************************/
static void TxIntrHandler(void *Callback)
{

    u32 IrqStatus;
    int TimeOut;
    XAxiDma *AxiDmaInst = (XAxiDma *)Callback;

    /* Read pending interrupts */
    IrqStatus = XAxiDma_IntrGetIrq(AxiDmaInst, XAXIDMA_DMA_TO_DEVICE);

    /* Acknowledge pending interrupts */

    XAxiDma_IntrAckIrq(AxiDmaInst, IrqStatus, XAXIDMA_DMA_TO_DEVICE);

    /*
	 * If no interrupt is asserted, we do not do anything
	 */
    if (!(IrqStatus & XAXIDMA_IRQ_ALL_MASK))
    {

        return;
    }

    /*
	 * If error interrupt is asserted, raise error flag, reset the
	 * hardware to recover from the error, and return with no further
	 * processing.
	 */
    if ((IrqStatus & XAXIDMA_IRQ_ERROR_MASK))
    {

        Error = 1;

        /*
		 * Reset should never fail for transmit channel
		 */
        XAxiDma_Reset(AxiDmaInst);

        TimeOut = RESET_TIMEOUT_COUNTER;

        while (TimeOut)
        {
            if (XAxiDma_ResetIsDone(AxiDmaInst))
            {
                break;
            }

            TimeOut -= 1;
        }

        return;
    }

    /*
	 * If Completion interrupt is asserted, then set the TxDone flag
	 */
    if ((IrqStatus & XAXIDMA_IRQ_IOC_MASK))
    {

        TxDone = 1;
    }
}

/*****************************************************************************/
/*
 *
 * This is the DMA RX interrupt handler function
 *
 * It gets the interrupt status from the hardware, acknowledges it, and if any
 * error happens, it resets the hardware. Otherwise, if a completion interrupt
 * is present, then it sets the RxDone flag.
 *
 * @param	Callback is a pointer to RX channel of the DMA engine.
 *
 * @return	None.
 *
 * @note		None.
 *
 ******************************************************************************/
static void RxIntrHandler(void *Callback)
{
    u32 IrqStatus;
    int TimeOut;
    XAxiDma *AxiDmaInst = (XAxiDma *)Callback;

    /* Read pending interrupts */
    IrqStatus = XAxiDma_IntrGetIrq(AxiDmaInst, XAXIDMA_DEVICE_TO_DMA);

    /* Acknowledge pending interrupts */
    XAxiDma_IntrAckIrq(AxiDmaInst, IrqStatus, XAXIDMA_DEVICE_TO_DMA);

    /*
	 * If no interrupt is asserted, we do not do anything
	 */
    if (!(IrqStatus & XAXIDMA_IRQ_ALL_MASK))
    {
        return;
    }

    /*
	 * If error interrupt is asserted, raise error flag, reset the
	 * hardware to recover from the error, and return with no further
	 * processing.
	 */
    if ((IrqStatus & XAXIDMA_IRQ_ERROR_MASK))
    {

        Error = 1;

        /* Reset could fail and hang
		 * NEED a way to handle this or do not call it??
		 */
        XAxiDma_Reset(AxiDmaInst);

        TimeOut = RESET_TIMEOUT_COUNTER;

        while (TimeOut)
        {
            if (XAxiDma_ResetIsDone(AxiDmaInst))
            {
                break;
            }

            TimeOut -= 1;
        }

        return;
    }

    /*
	 * If completion interrupt is asserted, then set RxDone flag
	 */
    if ((IrqStatus & XAXIDMA_IRQ_IOC_MASK))
    {

        RxDone = 1;
    }
}

/*****************************************************************************/
/*
 *
 * This function setups the interrupt system so interrupts can occur for the
 * DMA, it assumes INTC component exists in the hardware system.
 *
 * @param	IntcInstancePtr is a pointer to the instance of the INTC.
 * @param	AxiDmaPtr is a pointer to the instance of the DMA engine
 * @param	TxIntrId is the TX channel Interrupt ID.
 * @param	RxIntrId is the RX channel Interrupt ID.
 *
 * @return
 *		- XST_SUCCESS if successful,
 *		- XST_FAILURE.if not successful
 *
 * @note		None.
 *
 ******************************************************************************/
static int SetupIntrSystem(INTC *IntcInstancePtr, XAxiDma *AxiDmaPtr,
                           u16 TxIntrId, u16 RxIntrId)
{
    int Status;

#ifdef XPAR_INTC_0_DEVICE_ID

    /* Initialize the interrupt controller and connect the ISRs */
    Status = XIntc_Initialize(IntcInstancePtr, INTC_DEVICE_ID);
    if (Status != XST_SUCCESS)
    {

        xil_printf("Failed init intc\r\n");
        return XST_FAILURE;
    }

    Status = XIntc_Connect(IntcInstancePtr, TxIntrId,
                           (XInterruptHandler)TxIntrHandler, AxiDmaPtr);
    if (Status != XST_SUCCESS)
    {

        xil_printf("Failed tx connect intc\r\n");
        return XST_FAILURE;
    }

    Status = XIntc_Connect(IntcInstancePtr, RxIntrId,
                           (XInterruptHandler)RxIntrHandler, AxiDmaPtr);
    if (Status != XST_SUCCESS)
    {

        xil_printf("Failed rx connect intc\r\n");
        return XST_FAILURE;
    }

    /* Start the interrupt controller */
    Status = XIntc_Start(IntcInstancePtr, XIN_REAL_MODE);
    if (Status != XST_SUCCESS)
    {

        xil_printf("Failed to start intc\r\n");
        return XST_FAILURE;
    }

    XIntc_Enable(IntcInstancePtr, TxIntrId);
    XIntc_Enable(IntcInstancePtr, RxIntrId);

#else

    XScuGic_Config *IntcConfig;

    /*
	 * Initialize the interrupt controller driver so that it is ready to
	 * use.
	 */
    IntcConfig = XScuGic_LookupConfig(INTC_DEVICE_ID);
    if (NULL == IntcConfig)
    {
        return XST_FAILURE;
    }

    Status = XScuGic_CfgInitialize(IntcInstancePtr, IntcConfig,
                                   IntcConfig->CpuBaseAddress);
    if (Status != XST_SUCCESS)
    {
        return XST_FAILURE;
    }

    XScuGic_SetPriorityTriggerType(IntcInstancePtr, TxIntrId, 0xA0, 0x3);

    XScuGic_SetPriorityTriggerType(IntcInstancePtr, RxIntrId, 0xA0, 0x3);
    /*
	 * Connect the device driver handler that will be called when an
	 * interrupt for the device occurs, the handler defined above performs
	 * the specific interrupt processing for the device.
	 */
    Status = XScuGic_Connect(IntcInstancePtr, TxIntrId,
                             (Xil_InterruptHandler)TxIntrHandler, AxiDmaPtr);
    if (Status != XST_SUCCESS)
    {
        return Status;
    }

    Status = XScuGic_Connect(IntcInstancePtr, RxIntrId,
                             (Xil_InterruptHandler)RxIntrHandler, AxiDmaPtr);
    if (Status != XST_SUCCESS)
    {
        return Status;
    }

    XScuGic_Enable(IntcInstancePtr, TxIntrId);
    XScuGic_Enable(IntcInstancePtr, RxIntrId);

#endif

    /* Enable interrupts from the hardware */

    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)INTC_HANDLER, (void *)IntcInstancePtr);

    Xil_ExceptionEnable();

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
 *
 * This function disables the interrupts for DMA engine.
 *
 * @param	IntcInstancePtr is the pointer to the INTC component instance
 * @param	TxIntrId is interrupt ID associated w/ DMA TX channel
 * @param	RxIntrId is interrupt ID associated w/ DMA RX channel
 *
 * @return	None.
 *
 * @note		None.
 *
 ******************************************************************************/
static void DisableIntrSystem(INTC *IntcInstancePtr, u16 TxIntrId,
                              u16 RxIntrId)
{
#ifdef XPAR_INTC_0_DEVICE_ID
    /* Disconnect the interrupts for the DMA TX and RX channels */
    XIntc_Disconnect(IntcInstancePtr, TxIntrId);
    XIntc_Disconnect(IntcInstancePtr, RxIntrId);
#else
    XScuGic_Disconnect(IntcInstancePtr, TxIntrId);
    XScuGic_Disconnect(IntcInstancePtr, RxIntrId);
#endif
}
