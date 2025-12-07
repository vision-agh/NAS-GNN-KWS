import matplotlib.pyplot as plt
def visualize_events_and_graph(pos, edge_index):
    """
    pos: (N, 2) tensor containing [time, channel]
    edge_index: (2, E) tensor of edges
    """

    times = pos[:, 0].cpu().numpy()
    channels = pos[:, 1].cpu().numpy()

    fig, ax = plt.subplots(figsize=(10, 6))

    # ---------------------------------------------------
    # PLOT EVENTS
    # ---------------------------------------------------
    ax.scatter(times, channels, s=6, c='blue', label="events", alpha=0.6)

    # ---------------------------------------------------
    # PLOT GRAPH EDGES
    # ---------------------------------------------------
    edges = edge_index.cpu().numpy()  # shape (E, 2)

    for src, dst in edges:
        t1, c1 = times[src], channels[src]
        t2, c2 = times[dst], channels[dst]

        # skip self-loop lines (but you can enable)
        if src == dst:
            continue

        ax.plot([t1, t2], [c1, c2], linewidth=0.4, alpha=0.4, color='red')

    ax.set_xlabel("Time")
    ax.set_ylabel("Channel")
    ax.set_title("Event Graph Visualization")
    ax.legend()
    ax.grid(True)

    plt.show()