class MainSettings:
    """
    Class that collects the main configuration settings of pyNAVIS
    """

    def __init__(self, num_channels, mono_stereo = 0, address_size = 2, timestamp_size=4, ts_tick = 1, bin_size = 20000, on_off_both = 1, reset_timestamp = True,verbose=True):
        self.num_channels = num_channels
        self.mono_stereo = mono_stereo
        self.address_size = address_size
        self.timestamp_size = timestamp_size
        self.ts_tick = ts_tick
        self.bin_size = bin_size
        self.on_off_both = on_off_both
        self.reset_timestamp = reset_timestamp
        self.verbose = verbose


settings = MainSettings(num_channels=64, mono_stereo=1, on_off_both=1, address_size=2, timestamp_size=4, ts_tick=0.02)
