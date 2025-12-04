import math
import numpy as np

def nas_loader(file, settings):
    file = open(file, "rb")
    file_data = file.read()

    # Find last header line
    end_string = "#End Of ASCII Header\r\n"
    index = file_data.find(end_string.encode("utf-8"))
    if index != -1:
        index += len(end_string)
    else:
        index = 0

    # Raw data extraction
    num_spikes = int(math.floor(len(file_data[index:]) / (settings.address_size + settings.timestamp_size)))
    spikes_array = file_data[index:index + num_spikes * (settings.address_size + settings.timestamp_size)]
    address_param = ">u" + str(settings.address_size)
    timestamp_param = ">u" + str(settings.timestamp_size)
    bytes_struct = np.dtype(address_param + ", " + timestamp_param)

    spikes = np.frombuffer(spikes_array, bytes_struct)
    addresses = spikes['f0']
    timestamps = spikes['f1']

    timestamps = timestamps - 200_000

    return addresses, timestamps



# 0 - negative polarti, 1 - postivie polarity, 2 - negative polarity, 3 - positive polarity and so on...