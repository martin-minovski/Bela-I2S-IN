/*
 ____  _____ _        _    
| __ )| ____| |      / \   
|  _ \|  _| | |     / _ \  
| |_) | |___| |___ / ___ \ 
|____/|_____|_____/_/   \_\

The platform for ultra-low latency audio and sensor processing

http://bela.io

A project of the Augmented Instruments Laboratory within the
Centre for Digital Music at Queen Mary University of London.
http://www.eecs.qmul.ac.uk/~andrewm

(c) 2016 Augmented Instruments Laboratory: Andrew McPherson,
	Astrid Bin, Liam Donovan, Christian Heinrichs, Robert Jack,
	Giulio Moro, Laurel Pardue, Victor Zappi. All rights reserved.

The Bela software is distributed under the GNU Lesser General Public License
(LGPL 3.0), available here: https://www.gnu.org/licenses/lgpl-3.0.txt
*/

#include <Bela.h>
#include <GPIOcontrol.h>
#include <cmath>
#include <cstring>
#include "prussdrv.h"
#include "pruss_intc_mapping.h"
#include <inttypes.h>
#include "pru_gpio_bin.h"

// The definitions below are locations in PRU memory
// that need to match the PRU code
#define I2S_DELAY		0
#define I2S_COUNTER	1
#define BUFFER_START	2
#define SIGNAL_START	34

uint32_t *gPRUCommunicationMem = 0;

float gFrequency = 440.0;
float gPhase;
float gInverseSampleRate;

int gUpdateCount = 0;

bool load_pru(int pru_number);			// Load the PRU environment
bool start_pru(int pru_number);			// Start the PRU

float i2sBuffer[256];
int i2sBufferSize = 256;
int i2sBufferWriter = 128;
int i2sBufferReader = 0;
unsigned int* i2sBufferOffset;
unsigned int lastOffset = 0;
unsigned int i2sBufferSaved[32];

bool setup(BelaContext *context, void *userData)
{
	for (int i = 0; i < i2sBufferSize; i++) {
		i2sBuffer[i] = 0;
	}

	int pruNumber;		 // comes from userData

	if(userData == 0) {
		printf("Error: PRU number not provided. Are you using the right main.cpp file?\n");
		return false;
	}

	pruNumber = *((int *)userData);

	// Load PRU environment and map memory
	if(!load_pru(pruNumber)) {
		printf("Error: could not initialise user PRU code.\n");
		return false;
	}

	if(!start_pru(pruNumber)) {
		printf("Error: could not start user PRU code.\n");
		return false;
	}

	gInverseSampleRate = 1.0 / context->audioSampleRate;
	gPhase = 0.0;

	gPRUCommunicationMem[SIGNAL_START] = 1;

	return true;
}
void render(BelaContext *context, void *userData)
{
	i2sBufferOffset = &gPRUCommunicationMem[I2S_COUNTER];
	unsigned int i2sBufferOffsetSaved = *i2sBufferOffset;
	if (lastOffset != i2sBufferOffsetSaved) {
		memcpy(i2sBufferSaved, &gPRUCommunicationMem[BUFFER_START + (i2sBufferOffsetSaved != 0 ? 32 : 0)], 128);
		lastOffset = i2sBufferOffsetSaved;
		for (int i = 0; i < 32; i++) {
			int sample = i2sBufferSaved[i];
			if (sample > 32767) sample -= 65536;
			i2sBuffer[i2sBufferWriter++] = sample / 32767.0f;
		}
		if (i2sBufferWriter >= i2sBufferSize) i2sBufferWriter = 0;
	}

	for(unsigned int n = 0; n < context->audioFrames; n++) {
		for(unsigned int channel = 0; channel < context->audioOutChannels; channel++) {
			float belaSample = audioRead(context, n, channel);
			float i2sSample = i2sBuffer[i2sBufferReader++];
//			belaSample = 0;
//			i2sSample = 0;
			audioWrite(context, n, channel, belaSample + i2sSample);
		}
	}
	if (i2sBufferReader >= i2sBufferSize) i2sBufferReader = 0;
}

void cleanup(BelaContext *context, void *userData)
{
	int pruNumber = *((int *)userData);

    /* Disable PRU */
    prussdrv_pru_disable(pruNumber);
}

// Load environment for the second PRU, but don't run it yet
bool load_pru(int pru_number)
{
	void *pruMemRaw;
	uint32_t *pruMemInt;

	/* There is less to do here than usual for prussdrv because
	 * the core code will already have done basic initialisation
	 * of the library. */

    /* Allocate and initialize memory */
    if(prussdrv_open(PRU_EVTOUT_1)) {
    	rt_printf("Failed to open user-side PRU driver\n");
    	return false;
    }

	/* Map shared memory to a local pointer */
	prussdrv_map_prumem(PRUSS0_SHARED_DATARAM, (void **)&pruMemRaw);

	/* The first 0x800 is reserved by Bela. The next part is available
	   for our application. */
	pruMemInt = (uint32_t *)pruMemRaw;
	gPRUCommunicationMem = &pruMemInt[0x800/sizeof(uint32_t)];

	return true;
}

// Start the second PRU running
bool start_pru(int pru_number)
{
	if(prussdrv_exec_code(pru_number, PRUcode, sizeof(PRUcode))) {
		rt_printf("Failed to execute user-side PRU code\n");
		return false;
	}
	
	return true;
}

