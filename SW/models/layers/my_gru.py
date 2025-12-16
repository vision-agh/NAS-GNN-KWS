import torch
import torch.nn as nn
from models.layers.my_gru_cell import MyGRUCell

from models.layers.quantisation.observer import Observer, FakeQuantize, quantize_tensor, dequantize_tensor

class MyGRU(nn.Module):
    def __init__(self, input_size: int, 
                        hidden_size: int, 
                        num_bits: int):
        super(MyGRU, self).__init__()
        self.hidden_size = hidden_size

        self.gru = MyGRUCell(input_size, 
                                hidden_size, 
                                num_bits=num_bits)

    def forward(
        self,
        x: torch.Tensor,
        h: torch.Tensor = None,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        
        if h is None:
            if self.gru.quantize_mode.item():
                h = torch.full((x.size(0), self.hidden_size), self.gru.observer_hidden.zero_point, device=x.device, dtype=torch.int32)
            else:
                h = torch.full((x.size(0), self.hidden_size), 0.0, device=x.device)
        
        outputs = []
        for t in range(x.size(1)):
            x_in = x[:, t, :]
            h = self.gru(x_in, h)
            outputs.append(h.unsqueeze(1))
        output = torch.cat(outputs, dim=1)
        return output, h
    
    def calibrate(self):
        self.gru.calibrate()

    def quantize(self,
               observer_input: Observer = None,
               observer_output: Observer = None):
        
        self.gru.quantize(observer_input, observer_output)
    
    def compile(self):
        return torch.jit.script(self)
    