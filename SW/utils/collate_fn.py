import torch
from torch.nn.utils.rnn import pad_sequence

def collate_fn(data_list):
    x = torch.cat([data['x'] for data in data_list], dim=0)
    pos = torch.cat([data['pos'] for data in data_list], dim=0)

    edge_index = []
    offset = 0
    for d in data_list:
        edge_index.append(d['edge_index'] + offset)
        offset += d['x'].shape[0]
    edge_index = torch.cat(edge_index, dim=0)

    batch = torch.cat([
        torch.full((d['x'].shape[0],), i, dtype=torch.long)
        for i, d in enumerate(data_list)
    ], dim=0)

    # For recognition task
    y = torch.tensor([data['y'] for data in data_list], dtype=torch.long)

    # For KWS task
    cls_list = [d["cls_vec"] for d in data_list]
    conf_list = [d["conf_vec"] for d in data_list]

    # compute global mode for cls values efficiently
    cls_all = torch.cat(cls_list)
    cls_mode = torch.mode(cls_all).values   # scalar

    # pad conf_vec with zeros
    conf_vec = pad_sequence(conf_list, batch_first=True, padding_value=0)

    # pad cls_vec with mode value
    cls_vec = pad_sequence(cls_list, batch_first=True, padding_value=int(cls_mode))

    return {"x": x,
            "pos": pos,
            "edge_index": edge_index,
            "y": y,
            "cls_vec": cls_vec,
            "conf_vec": conf_vec,
            "batch": batch}