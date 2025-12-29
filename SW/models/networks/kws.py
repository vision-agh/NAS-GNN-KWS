import torch
import torch.nn.functional as F
from torch.nn import Module

from models.layers.quantisation.observer import Observer, FakeQuantize, quantize_tensor, dequantize_tensor

from models.layers.my_linear import MyLinear
from models.layers.my_pointnet import MyPointNetConv
from models.layers.my_pooling_moving import MyMovingGlobalPooling
from models.layers.my_gru import MyGRU

# from utils.generate_outputs import conv_gen_out, conv_first_gen_out, graph_gen_out, vector_out

class KWS(Module):
    def __init__(self, 
                 config):
        super(KWS, self).__init__()
        self.config = config

        conv_ch = config.model.conv_channels
        conv_bits = config.model.conv_bits

        pooling_op = config.model.global_pooling

        stem_ch = config.model.stem_channels
        stem_bits = config.model.stem_bits

        rnn_ch = config.model.rnn_channels
        rnn_bits = config.model.rnn_bits

        cls_linear_ch = config.model.cls_linear_channels
        cls_linear_bits = config.model.cls_linear_bits

        conf_linear_ch = config.model.conf_linear_channels
        conf_linear_bits = config.model.conf_linear_bits

        num_classes = config.model.num_classes

        input_dim = config.model.features
        
        self.conv1 = MyPointNetConv(input_dim+2, conv_ch[0],  bias=False, num_bits=conv_bits[0], first_layer=True, cfg=config)
        self.conv2 = MyPointNetConv(conv_ch[0]+2, conv_ch[1], bias=False, num_bits=conv_bits[1], cfg=config)
        self.conv3 = MyPointNetConv(conv_ch[1]+2, conv_ch[2], bias=False, num_bits=conv_bits[2], cfg=config)
        self.conv4 = MyPointNetConv(conv_ch[2]+2, conv_ch[3], bias=False, num_bits=conv_bits[3], cfg=config)
        
        self.pooling = MyMovingGlobalPooling(pooling_op, num_bits=conv_bits[3], config=config)

        self.fc1 = MyLinear(conv_ch[3], stem_ch, bias= True, num_bits=stem_bits)
        self.fc2 = MyLinear(stem_ch, stem_ch, bias=True, num_bits=stem_bits)

        self.rnn = MyGRU(input_size=stem_ch, hidden_size=rnn_ch, num_bits=rnn_bits)

        self.cls = MyLinear(cls_linear_ch, num_classes, bias=True, num_bits=cls_linear_bits)
        self.conf = MyLinear(conf_linear_ch, 1, bias=True, num_bits=conf_linear_bits)

        '''Modes for calibration and quantization'''
        self.register_buffer('calib_mode', torch.tensor(False, requires_grad=False))
        self.register_buffer('quantize_mode', torch.tensor(False, requires_grad=False))


    def relu(self, x, observer):
        if not self.quantize_mode:
            return F.relu(x)
        else:
            # In quantize mode, simulate quantized ReLU
            x[x < observer.zero_point] = observer.zero_point
            return x

    def forward(self, data):
        x, pos, edge_index, batch = data['x'], data['pos'], data['edge_index'], data['batch']

        ###############################################################
        # POSITIONAL NORMALISATION, REMOVE IF YOU TEST PREVIOUS MODELS!
        pos_norm = pos.clone()
        pos_norm[:,0] = pos_norm[:,0] * (- 1 / (self.config.dataset.high_time_radius / 1000000))
        channels = self.config.dataset.num_channels if not self.config.dataset.polarity else (self.config.dataset.num_channels * 2)

        pos_norm[:,1] = pos_norm[:,1] + self.config.dataset.channel_radius / channels
        pos_norm[:,1] = pos_norm[:,1] * (channels / (self.config.dataset.channel_radius)) 
        ###############################################################


        x = self.conv1(x, pos_norm, edge_index)
        x = self.relu(x, self.conv1.observer_output)
        x = self.conv2(x, pos_norm, edge_index)
        x = self.relu(x, self.conv2.observer_output)
        x = self.conv3(x, pos_norm, edge_index)
        x = self.relu(x, self.conv3.observer_output)
        x = self.conv4(x, pos_norm, edge_index)
        x = self.relu(x, self.conv4.observer_output)

        x = self.pooling(x, pos, batch, self.conv4.observer_output)
        x = self.fc1(x)
        x = self.relu(x, self.fc1.observer_output)
        x = self.fc2(x)
        x = self.relu(x, self.fc2.observer_output)
        x = self.rnn(x)[0]

        conf = self.conf(x)
        conf = conf.squeeze(2)

        cls = self.cls(x)
        cls = cls.permute(0, 2, 1)

        if self.quantize_mode.item():
            conf = self.conf.observer_output.dequantize_tensor(conf)
            cls = self.cls.observer_output.dequantize_tensor(cls)
        return conf, cls
    
    def calibrate(self):
        self.calib_mode.fill_(True)
        self.conv1.calibrate()
        self.conv2.calibrate()
        self.conv3.calibrate()
        self.conv4.calibrate()
        self.pooling.calibrate()
        self.fc1.calibrate()
        self.fc2.calibrate()
        self.rnn.calibrate()    
        self.cls.calibrate()
        self.conf.calibrate()

    def quantize(self):
        self.quantize_mode.fill_(True)

        self.conv1.quantize()
        self.conv2.quantize(observer_input=self.conv1.observer_output)
        self.conv3.quantize(observer_input=self.conv2.observer_output)
        self.conv4.quantize(observer_input=self.conv3.observer_output)
        self.pooling.quantize()
        self.fc1.quantize(observer_input=self.conv4.observer_output)
        self.fc2.quantize(observer_input=self.fc1.observer_output)
        self.rnn.quantize(observer_input=self.fc2.observer_output)
        self.cls.quantize(observer_input=self.rnn.gru.observer_hidden)
        self.conf.quantize(observer_input=self.rnn.gru.observer_hidden)