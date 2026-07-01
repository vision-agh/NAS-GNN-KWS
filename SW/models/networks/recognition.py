import torch
import torch.nn.functional as F
from torch.nn import Module, ModuleList, Linear, Dropout, Sequential
import numpy as np

from models.layers.my_pointnet import MyPointNetConv
from models.layers.my_pooling import MyGlobalPooling
from models.layers.my_linear import MyLinear

from utils.generate_outputs import conv_gen_out, conv_first_gen_out, graph_gen_out, vector_out, vector_out_single

class Recognition(Module):
    def __init__(self, 
                 config):
        super(Recognition, self).__init__()
        
        self.config = config

        conv_ch = config.model.conv_channels
        conv_bits = config.model.conv_bits

        linear_ch = config.model.linear_channels
        num_classes = config.model.num_classes

        input_dim = config.model.features + (0 if config.dataset.polarity else 1)
        
        self.conv1 = MyPointNetConv(input_dim+2, conv_ch[0], bias=False, num_bits=conv_bits[0], first_layer=True, cfg=config)
        self.conv2 = MyPointNetConv(conv_ch[0]+2, conv_ch[1], bias=False, num_bits=conv_bits[1], cfg=config)
        self.conv3 = MyPointNetConv(conv_ch[1]+2, conv_ch[2], bias=False, num_bits=conv_bits[2], cfg=config)
        self.conv4 = MyPointNetConv(conv_ch[2]+2, conv_ch[3], bias=False, num_bits=conv_bits[3], cfg=config)
        
        self.pooling = MyGlobalPooling(config.model.global_pooling, num_bits=conv_bits[3])

        self.fc1 = MyLinear(conv_ch[3], linear_ch, bias= True, num_bits=conv_bits[3])
        self.fc2 = MyLinear(linear_ch, num_classes, bias=True, num_bits=conv_bits[3])

        self.register_buffer('calib_mode', torch.tensor(False, requires_grad=False))
        self.register_buffer('quantize_mode', torch.tensor(False, requires_grad=False))


    def forward(self, data):
        outputs = []
        x, pos, edge_index, batch = data['x'], data['pos'], data['edge_index'], data['batch']
        x = self.conv1(x, pos, edge_index)
        x = self.conv2(x, pos, edge_index)
        x = self.conv3(x, pos, edge_index)
        x = self.conv4(x, pos, edge_index)
        x = self.pooling(x, batch, self.conv4.observer_output)

        x = self.fc1(x)
        if not self.quantize_mode:
            x = F.relu(x)
        else:
            x[x < self.fc1.observer_output.zero_point] = self.fc1.observer_output.zero_point
        x = self.fc2(x)

        if self.quantize_mode.item():
            x = self.fc2.observer_output.dequantize_tensor(x)
        return x
    
    def calibrate(self):
        self.calib_mode.fill_(True)
        self.conv1.calibrate()
        self.conv2.calibrate()
        self.conv3.calibrate()
        self.conv4.calibrate()
        self.pooling.calibrate()
        self.fc1.calibrate()
        self.fc2.calibrate()

    def quantize(self):
        self.quantize_mode.fill_(True)
        self.conv1.quantize()
        self.conv2.quantize(observer_input=self.conv1.observer_output)
        self.conv3.quantize(observer_input=self.conv2.observer_output)
        self.conv4.quantize(observer_input=self.conv3.observer_output)
        self.pooling.quantize()
        self.fc1.quantize(observer_input=self.conv4.observer_output)
        self.fc2.quantize(observer_input=self.fc1.observer_output)