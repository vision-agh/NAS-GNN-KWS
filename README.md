# End-to-End Keyword Spotting on FPGA Using Graph Neural Networks with a Neuromorphic Auditory Sensor

This repository provides the end-to-end FPGA implementation of the keyword spotting system utilising the Neuromorphic Auditory Sensor and Graph Neural Networks as published and presented during the 2026 ARC conference.

<div align="center">
  <img src="assets/diagram.png" width="1000px"/><br>
    <p style="font-size:1.5vw;">The proposed architecture is illustrated with the sensor and filtering modules highlighted in green, the feature extraction stage in blue, and the MaxPool and network head modules in yellow. The scheduling mechanism is marked in purple, while the timestamp propagation mechanism is indicated in red.. </p>
</div>


## Authors

|Name|Role|Contact|Affilation|
|-|-|-|-|
|Wiktor Matykiewicz|Student|wiktor.matykiewicz.03@gmail.com|AGH University of Krakow, Poland|
|Piotr Wzorek|PhD Student|pwzorek@agh.edu.pl|AGH University of Krakow, Poland|
|Kamil Jeziorek|PhD Student|kjeziorek@agh.edu.pl|AGH University of Krakow, Poland|
|Tomás Muñoz|Student|tmunoz1@us.es|University of Seville, Spain|
|Antonio Rios-Navarro|Supervisor|ARIOS@US.ES|University of Seville, Spain|
|Angel Jiménez-Fernández|Supervisor|angel@us.es|University of Seville, Spain|
|Tomasz Kryjak|Supervisor|kryjak@agh.edu.pl|AGH University of Krakow, Poland|

## Getting Started

The project is divided into two parts: Software and Hardware.

### Software

The software part of the project is responsible for training and evaluating GCN models (PyTroch implementation).

### Hardware

The hardware part of the project is responsible for implementing both the NAS and the GCN on the FPGA (SystemVerilog/VHDL implementation). The hardware part is located in the `HW` folder. The adopted NAS implementation is generated with [OpenNAS](https://github.com/RTC-research-group/OpenNAS).

## Citation
If you find this project useful in your research, please consider citing our work:

```BibTeX
@article{matykiewicz2026end,
  title={End-to-End Keyword Spotting on FPGA Using Graph Neural Networks with a Neuromorphic Auditory Sensor},
  author={Matykiewicz, Wiktor and Wzorek, Piotr and Jeziorek, Kamil and Muñoz, Tomás and Rios-Navarro, Antonio and Jiménez-Fernández, Angel and Kryjak, Tomasz},
  journal={arXiv preprint arXiv:2605.09570},
  year={2026}
}
```