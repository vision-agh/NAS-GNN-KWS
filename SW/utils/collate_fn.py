import torch

def collate_fn(data_list):
    x = torch.cat([data['x'] for data in data_list], dim=0)
    pos = torch.cat([data['pos'] for data in data_list], dim=0)

    edge_index = []
    offset = 0
    for d in data_list:
        edge_index.append(d['edge_index'] + offset)
        offset += d['x'].shape[0]
    edge_index = torch.cat(edge_index, dim=0)

    y = torch.tensor([data['y'] for data in data_list], dtype=torch.long)

    batch = torch.cat([
        torch.full((d['x'].shape[0],), i, dtype=torch.long)
        for i, d in enumerate(data_list)
    ], dim=0)
    return {"x": x,
            "pos": pos,
            "edge_index": edge_index,
            "y": y,
            "batch": batch}