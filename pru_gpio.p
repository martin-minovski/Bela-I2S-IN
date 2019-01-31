.origin 0
.entrypoint START

// -----------
// Definitions
// -----------

#define I2S_GPIO 0x481AC138
#define GPIO0 0x44E07000
#define GPIO1 0x4804C000
#define GPIO2 0x481ac000
#define GPIO_OE 0x134 
#define GPIO_DATAIN 0x138
#define GPIO_CLEARDATAOUT 0x190
#define GPIO_SETDATAOUT 0x194

#define PRU0_ARM_INTERRUPT 19	// Interrupt signalling we're done
#define PRU1_ARM_INTERRUPT 20	// Interrupt signalling a block is ready

#define SHARED_COMM_MEM_BASE_SYS  0x00010000  // Location where comm flags are written
#define COMM_SHOULD_STOP      0		  // Set to be nonzero when loop should stop
#define COMM_CURRENT_BUFFER   4           // Which buffer we are on
#define COMM_BUFFER_FRAMES    8           // How many frames per buffer
#define COMM_SHOULD_SYNC      12          // Whether to synchronise to an external clock
#define COMM_SYNC_ADDRESS     16          // Which memory address to find the GPIO on
#define COMM_SYNC_PIN_MASK    20          // Which pin to read for the sync
#define COMM_LED_ADDRESS      24          // Which memory address to find the status LED on
#define COMM_LED_PIN_MASK     28          // Which pin to write to change LED
#define COMM_FRAME_COUNT      32	  // How many frames have elapse since beginning
#define COMM_USE_SPI          36          // Whether or not to use SPI ADC and DAC
#define COMM_NUM_CHANNELS     40	  // Low 2 bits indicate 8 [0x3], 4 [0x1] or 2 [0x0] channels
#define COMM_USE_DIGITAL      44	  // Whether or not to use DIGITAL
#define COMM_PRU_NUMBER       48          // Which PRU this code is running on
#define COMM_MUX_CONFIG       52          // Whether to use the mux capelet, and how many channels
#define COMM_MUX_END_CHANNEL  56          // Which mux channel the last buffer ended on

#define SHARED_COMM_MEM_BASE_USER  0x00010800   // Comm memory available for this program

// ---------------------------------------------------
// Your definitions within shared communication memory
// ---------------------------------------------------

#define I2S_COMM_DELAY	        0
#define I2S_COUNTER	        4
#define BUFFER_START	        8
#define SIGNAL_START	        136
	 

// ------------		
// Register map
// ------------

// --- r1, r2, r3 are used for temporary storage ---

// r4 to r24 available

#define reg_comm_sys_addr		r25		// Memory address for communicating with ARM, Bela core
#define reg_comm_user_addr		r26		// Memory address for communicating with ARM, user code

// --- r27, r28 used in macros ---

// r29 to r31 available


// -------------
// Useful macros
// -------------

// GPIO_DIRECTION: Set the direction of a GPIO pin
// Parameters:
//   gpio_base: address of the particular GPIO peripheral (e.g. GPIO1)
//   gpio_num_bit: which bit number to change (0 to 31)
//   output        zero for input, nonzero for output
// Uses registers: r27, r28

.macro GPIO_DIRECTION
.mparam gpio_base, gpio_num_bit, output
    MOV r27, gpio_base
	MOV r28, GPIO_OE
	ADD r27, r27, r28
	MOV r28, output
	QBEQ SET_INPUT, r28, 0
SET_OUTPUT: // Pin should become an output
	LBBO r28, r27, 0, 4		// Load current OE register to R28
	CLR r28, gpio_num_bit
    QBA DONE
SET_INPUT: // Pin should become an input
	LBBO r28, r27, 0, 4		// Load current OE register to R28
	SET r28, gpio_num_bit
DONE:
	SBBO r28, r27, 0, 4
.endm

// GPIO_WRITE: Set the value of a GPIO output pin
// Parameters:
//   gpio_base: address of the particular GPIO peripheral (e.g. GPIO1)
//   gpio_num_bit: which bit number to change (0 to 31)
//   value:        whether pin should be high (nonzero) or low (zero)
// Uses registers: r27, r28

.macro GPIO_WRITE
.mparam gpio_base, gpio_num_bit, value
	MOV r27, gpio_base
	MOV r28, value
	QBEQ SET_LOW, r28, 0   
SET_HIGH:
	MOV r28, GPIO_SETDATAOUT
	ADD r27, r27, r28
	QBA DONE
SET_LOW:
	MOV r28, GPIO_CLEARDATAOUT
	ADD r27, r27, r28
DONE:
	LDI r28, 0
	SET r28, gpio_num_bit
	SBBO r28, r27, 0, 4
.endm

// GPIO_READ: Read the value of a GPIO output pin
// Parameters:
//   gpio_base: address of the particular GPIO peripheral (e.g. GPIO1)
//   gpio_num_bit: which bit number to change (0 to 31)
//   value:        will be set to value read from the pin (low = zero)         
// Uses registers: r27, r28

.macro GPIO_READ
.mparam gpio_base, gpio_num_bit, value
    MOV r27, gpio_base
	//MOV r28, GPIO_DATAIN
	//ADD r27, r27, r28
	LBBO r28, r27, 0, 4			// Load GPIO DATAIN register
	QBBC READ_WAS_LOW, r28, gpio_num_bit
READ_WAS_HIGH:
	LDI value, 1
	QBA DONE
READ_WAS_LOW:
    LDI value, 0
DONE:
.endm

.macro GPIO_REREAD
.mparam gpio_base, gpio_num_bit, value
	QBBC READ_WAS_LOW, r28, gpio_num_bit
READ_WAS_HIGH:
	LDI value, 1
	QBA DONE
READ_WAS_LOW:
    LDI value, 0
DONE:
.endm

// DELAY: Wait (busy loop) for a specified time
// Parameters:
//   count: how long to wait, in 10ns increments
//          this macro also adds a constant 10ns at the beginning 
// Uses registers: r27

.macro DELAY
.mparam count
    MOV r27, count
DELAY_LOOP:
    SUB r27, r27, 1
	QBNE DELAY_LOOP, r27, 0
.endm

START:
     // Load useful registers for addressing SPI
     MOV reg_comm_sys_addr, SHARED_COMM_MEM_BASE_SYS
	 MOV reg_comm_user_addr, SHARED_COMM_MEM_BASE_USER
	 
     // Find out which PRU we are running on
     // This affects the following offsets
	 // The value in this register indicates which
	 // PRU is core Bela code runs on, so we must
	 // be on the other one.
     MOV  r0, 0x22000      // PRU0 control register offset
     LBBO r2, reg_comm_sys_addr, COMM_PRU_NUMBER, 4
     QBEQ PRU_NUMBER_CHECK_DONE, r2, 1
     MOV  r0, 0x24000      // PRU1 control register offset
PRU_NUMBER_CHECK_DONE:	
	
     // Set up c24 and c25 offsets with CTBIR register
     // Thus C24 points to start of PRU0 RAM
     OR  r3, r0, 0x20      // CTBIR0
     MOV r2, 0
     SBBO r2, r3, 0, 4

     // Set up c28 pointer offset for shared PRU RAM
     OR r3, r0, 0x28       // CTPPR0
     MOV r2, 0x00000120    // To get address 0x00012000
     SBBO r2, r3, 0, 4

     // Set ARM such that PRU can write to registers
     LBCO r0, C4, 4, 4
     CLR r0, r0, 4
     SBCO r0, C4, 4, 4
	 
I2S_SETUP:
     // ------------------------
     // Your init code goes here
     // ------------------------	 

     GPIO_DIRECTION GPIO2, 2, 0
     GPIO_DIRECTION GPIO2, 3, 0
     GPIO_DIRECTION GPIO2, 4, 0
     //GPIO_DIRECTION GPIO2, 5, 0


     LDI r4, 0
     LDI r5, 0
     LDI r6, 0
     LDI r7, 0
     LDI r8, 0 // wait for signal loop
     LDI r9, 0
     LDI r10, 0 // sample storage
     LDI r11, 0 // bit clock
     LDI r12, 0 // data bit
     LDI r13, 0 // word clock
     LDI r14, 0
     LDI r15, 0
     LDI r16, 0
     LDI r17, 0
     LDI r18, 0
     LDI r19, 0 // used as null
     LDI r20, 0
     LDI r21, 0x108 // end of buffer
     LDI r22, 0x88  // halfway buffer
     LDI r23, BUFFER_START // buffer write pointer
     LDI r24, BUFFER_START // buffer start pointer (doesn't change)
     LDI r2, 0

WAIT_FOR_SIGNAL:
     LDI r8, 0
     SBBO r8, reg_comm_user_addr, SIGNAL_START, 4
WAIT_FOR_SIGNAL_LOOP:
     LBBO r8, reg_comm_user_addr, SIGNAL_START, 4
     QBEQ WAIT_FOR_SIGNAL_LOOP, r8, 0
     DELAY 200000

I2S_LOOP:

     GPIO_READ I2S_GPIO, 2, r11.b0
     // Only proceed if the value is new
     QBEQ I2S_LOOP, r11.b0, r11.b1
     // Save new value
     MOV r11.b1, r11.b0
     // Only proceed on rising edge
     QBEQ I2S_LOOP, r11.b0, 0

     // Stabilize
     DELAY 5

     // Read next databit
     GPIO_REREAD I2S_GPIO, 4, r12.b0
     // Bitwise shift
     LSL r10, r10, 1
     // Add last bit
     OR r10, r10, r12.b0

     // Read word
     GPIO_REREAD I2S_GPIO, 3, r13.b0
     // Only proceed if the value is new
     QBEQ I2S_LOOP, r13.b0, r13.b1
     // Save new value
     MOV r13.b1, r13.b0

     // Store sample
     SBBO r10, reg_comm_user_addr, r23, 4

     // Clear sample register
     LDI r10, 0

     // Increment buffer pointer
     ADD r23, r23, 4
     QBEQ BUFFER_HALFWAY, r23, r22
     QBEQ BUFFER_FULL, r23, r21
     QBA I2S_LOOP

BUFFER_FULL:
     SBBO r23, reg_comm_user_addr, I2S_COUNTER, 4
     MOV r23, r24
     QBA I2S_LOOP

BUFFER_HALFWAY:
     SBBO r19, reg_comm_user_addr, I2S_COUNTER, 4
     QBA I2S_LOOP


I2S_CLEANUP:
     // ---------------------------
	 // Your cleanup code goes here
	 // ---------------------------
	 // ain't nobody got time for that
	 
	 
CLEANUP_DONE:
     // Signal the ARM that we have finished 
     MOV R31.b0, PRU0_ARM_INTERRUPT + 16
     HALT
