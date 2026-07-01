import math
import numpy as np

def nas_loader(file, config):
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
    num_spikes = int(math.floor(len(file_data[index:]) / (config.address_size + config.timestamp_size)))
    spikes_array = file_data[index:index + num_spikes * (config.address_size + config.timestamp_size)]
    address_param = ">u" + str(config.address_size)
    timestamp_param = ">u" + str(config.timestamp_size)
    bytes_struct = np.dtype(address_param + ", " + timestamp_param)

    spikes = np.frombuffer(spikes_array, bytes_struct)
    addresses = spikes['f0']
    timestamps = spikes['f1']

    # Normalize timestamps
    timestamps = (timestamps - timestamps[0]) * config.ts_tick

    # Remove noise events that occur around 0-1000 microseconds
    valid_indices = np.where(timestamps >= 1000)[0]
    addresses = addresses[valid_indices]
    timestamps = timestamps[valid_indices]

    if timestamps.size == 0:
    # Option A: return arrays with a single dummy event (e.g., address=0, timestamp=0)
        return np.array([0], dtype=np.uint32), np.array([0], dtype=np.float32)

    timestamps = timestamps - timestamps[0]
    return addresses, timestamps