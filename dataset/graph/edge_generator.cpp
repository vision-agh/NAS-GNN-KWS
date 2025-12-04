#include <torch/torch.h>
#include <vector>
#include <tuple>
#include <iostream>

class EdgeGenerator {
public:
    int num_channels;
    float channel_radius;
    float time_radius;
    float time_window;
    int skip_channels;
    std::string features;

    EdgeGenerator(int num_channels, float channel_radius, float time_radius, 
                  float time_window, int skip_channels, std::string features)
        : num_channels(num_channels), channel_radius(channel_radius),
          time_radius(time_radius), time_window(time_window), 
          skip_channels(skip_channels), features(features) {}

    // ------------------------------------------------------------------
    // RETURN: edges, features, positions
    // ------------------------------------------------------------------
    std::tuple<torch::Tensor, torch::Tensor, torch::Tensor> generate_edges(
        torch::Tensor times, torch::Tensor channels, py::object polarity_obj = py::none())
    {
        std::vector<std::pair<int, int>> edges;
        std::vector<std::array<float,3>> feature;       // always 3 dims
        std::vector<std::array<float,2>> positions;     // <---- NEW
        feature.reserve(times.size(0));
        positions.reserve(times.size(0));               // <---- NEW

        std::vector<std::pair<float, int>> channel_last_event(num_channels, {0, -1});

        auto times_data = times.data_ptr<float>();
        auto channels_data = channels.data_ptr<float>();

        // -----------------------------------------
        // OPTIONAL polarity
        bool use_polarity = false;
        const float* polarity_data = nullptr;

        if (!polarity_obj.is_none()) {
            torch::Tensor pol = polarity_obj.cast<torch::Tensor>();
            polarity_data = pol.data_ptr<float>();
            use_polarity = true;
        }
        // -----------------------------------------

        for (int idx = 0; idx < times.size(0); ++idx) {

            float time = times_data[idx*2];
            int channel = static_cast<int>(channels_data[idx*2]);

            // -----------------------------------------
            // STORE POSITION OF ACCEPTED EVENT
            positions.push_back({time, float(channel)});
            // -----------------------------------------

            float sum_t = 0;
            float sum_channel = 0;
            int sum_idx = 0;

            edges.emplace_back(idx, idx); // Self-loop

            for (int n_channel = channel - static_cast<int>(channel_radius); 
                 n_channel <= channel + static_cast<int>(channel_radius); 
                 n_channel += skip_channels) 
            {
                if (n_channel < 0 || n_channel >= num_channels) {
                    continue;
                }

                if (channel_last_event[n_channel].second != -1) {
                    float n_time = channel_last_event[n_channel].first;
                    int n_idx = channel_last_event[n_channel].second;

                    if (time - n_time <= time_radius) {
                        edges.emplace_back(idx, n_idx);

                        if (features == "local") {
                            sum_t += (time - n_time);
                            sum_channel += (channel - n_channel);
                        } else if (features == "global") {
                            sum_t += n_time;
                            sum_channel += n_channel;
                        }

                        ++sum_idx;
                    }
                }
            }

            float mean_t = sum_idx > 0 ? std::round(sum_t / sum_idx) : 0;
            float mean_channel = sum_idx > 0 ? std::round(sum_channel / sum_idx) : 0;

            channel_last_event[channel] = {time, idx};

            float ft, fc;
            if (features == "local") {
                ft = mean_t / time_radius;
                fc = mean_channel / channel_radius;
            } else {
                ft = mean_t / time_window;
                fc = mean_channel / num_channels;
            }

            float pol = use_polarity ? polarity_data[idx] : 0.0f;

            feature.push_back({ft, fc, pol});
        }

        torch::Tensor edge_tensor =
            torch::from_blob(edges.data(), {(long)edges.size(), 2}, torch::kInt32).clone();

        torch::Tensor full_feat =
            torch::from_blob(feature.data(), {(long)feature.size(), 3}, torch::kFloat32).clone();

        torch::Tensor out_feat = use_polarity ?
            full_feat.index({torch::indexing::Slice(), torch::indexing::Slice(0,3)}) :
            full_feat.index({torch::indexing::Slice(), torch::indexing::Slice(0,2)});

        // -----------------------------------------------------
        // RETURN POSITIONS AS A TENSOR (N × 2)
        // -----------------------------------------------------
        torch::Tensor pos_tensor =
            torch::from_blob(positions.data(), {(long)positions.size(), 2}, torch::kFloat32).clone();

        return {edge_tensor.contiguous(), out_feat, pos_tensor};
    }
};

PYBIND11_MODULE(edge_generator, m) {
    pybind11::class_<EdgeGenerator>(m, "EdgeGenerator")
        .def(pybind11::init<int, float, float, float, int, std::string>())
        .def("generate_edges", &EdgeGenerator::generate_edges,
             pybind11::arg("times"),
             pybind11::arg("channels"),
             pybind11::arg("polarity") = py::none());
}
