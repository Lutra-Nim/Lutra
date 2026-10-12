import registers

proc random*(): uint32 =
  ## From the hardware's generator. Its noise comes from the radio or the ADC,
  ## and with neither running, as now, the numbers are not fit for keys.
  randomNumber[]
