## This project uses the second PRU of the Beaglebone Black to read a 44kHz I2S stream and mix it with Bela's analog audio

#### Tested on Beaglebone Black Wireless

Pins:
- BCLK - P8_7 - P9_31 (shared clock)
- WSEL - P8_8 - P9_29 (shared clock)
- DATA IN - P8_9

The 3-way connections mean that both PRUs will be synchronized by the external I2S clocks. 

To disable Bela's internal clocks, set the following registers in /root/Bela/core/I2c_Codec.cpp:

- 0x08 to 0x0 - Bela codec should use the McASP pins as clock inputs
- 0x09 to 0x0 - Switch to standard I2S mode

As well as McASP registers in /root/Bela/pru/pru_rtaudio.p:

- MCASP_RFMT to 0x1807C - 1 bit delay, MSB first, 16bit, CFG bus, rotate by 16
- MCASP_XFMT to 0x1807C - ditto
- MCASP_AFSRCTL to 0x101 - I2S mode, falling edge frame clock
- MCASP_AFSXCTL to 0x101 - ditto
- MCASP_ACLKXCTL to 0x80 - transmit on falling edge

Since we've changed the McASP format to standard I2S, we can also use pin P9_28 as I2S data output.

Also note that if the I2S clocks stop running (that happens when you stop ALSA playback for instance), Bela will crash with message "PRU stopped responding".
To prevent that, comment out the line that contains "exit(1)" in /root/Bela/core/PRU.cpp along with the fprintf messages surrounding it. Don't comment out the task_sleep_ns call.
