#include <torch/torch.h>
#include <vector>
#include <tuple>
#include <iostream>
#include <cmath>

class EdgeGenerator {
public:
    int num_channels;
    float time_window;
    float channel_radius;
    float low_time_radius;
    float high_time_radius;
    int skip_channels;
    std::string features;
    bool use_filtration;
    int div_factor;
    int weight;
    std::vector<int> thresholds;

    EdgeGenerator(
                int num_channels, 
                float time_window, 
                float channel_radius, 
                float low_time_radius, 
                float high_time_radius, 
                int skip_channels, 
                std::string features,
                bool use_filtration,
                int div_factor,
                int weight,
                std::vector<int> thresholds)

        :   num_channels(num_channels), 
            time_window(time_window), 
            channel_radius(channel_radius),
            low_time_radius(low_time_radius), 
            high_time_radius(high_time_radius), 
            skip_channels(skip_channels), 
            features(features),
            use_filtration(use_filtration),
            div_factor(div_factor),
            weight(weight),
            thresholds(thresholds) {}

    // ------------------------------------------------------------------
    // RETURN: edges, features, positions
    // ------------------------------------------------------------------
    std::tuple<torch::Tensor, torch::Tensor, torch::Tensor> generate_edges(
        torch::Tensor times, torch::Tensor channels, py::object polarity_obj = py::none())
    {
        std::vector<std::pair<int, int>> edges;
        std::vector<std::array<float,3>> feature;
        std::vector<std::array<float,2>> positions;
        feature.reserve(times.size(0));
        positions.reserve(times.size(0));

        std::vector<std::pair<float, int>> channel_last_event(num_channels, {0, -1});
        std::vector<std::pair<float, float>> filter_potential(num_channels, {0, 0});

        auto times_data = times.data_ptr<float>();
        auto channels_data = channels.data_ptr<float>();
        int real_idx = 0;

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
            // FILTERING BASED ON TIME AND POTENTIAL
            // -----------------------------------------
            
            float last_time = filter_potential[channel].first;
            float potential = filter_potential[channel].second;

            float delta_t = time - last_time;
            int decay = floor(delta_t / (1 << div_factor));
            potential = std::max(0.0f, potential - float(decay));
            potential += float(weight);

            filter_potential[channel] = {time, potential};
            
            if (use_filtration) {
                if (potential < thresholds[channel]) {
                    continue;
                }
            }

            potential = 0.0f;
            filter_potential[channel] = {time, potential};

            // -----------------------------------------
            // STORE POSITION OF ACCEPTED EVENT
            positions.push_back({time, float(channel)});
            // -----------------------------------------

            float sum_t = 0;
            float sum_channel = 0;
            int sum_idx = 0;

            edges.emplace_back(real_idx, real_idx);

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

                    if ((time - n_time >= low_time_radius) && (time - n_time <= high_time_radius)) {
                        edges.emplace_back(real_idx, n_idx);

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

            channel_last_event[channel] = {time, real_idx};

            float ft, fc;
            if (features == "local") {
                ft = mean_t / high_time_radius;
                fc = mean_channel / channel_radius;
            } else {
                ft = mean_t / time_window;
                fc = mean_channel / num_channels;
            }

            float pol = use_polarity ? polarity_data[real_idx] : 0.0f;

            feature.push_back({ft, fc, pol});
            ++real_idx;
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
        .def(pybind11::init<int, float, float, float, float, int, std::string, bool, int, int, std::vector<int>>(),
             pybind11::arg("num_channels"),
             pybind11::arg("time_window"),
             pybind11::arg("channel_radius"),
             pybind11::arg("low_time_radius"),
             pybind11::arg("high_time_radius"),
             pybind11::arg("skip_channels"),
             pybind11::arg("features"),
             pybind11::arg("use_filtration"),
             pybind11::arg("div_factor"),
             pybind11::arg("weight"),
             pybind11::arg("thresholds"))
        .def("generate_edges", &EdgeGenerator::generate_edges,
             pybind11::arg("times"),
             pybind11::arg("channels"),
             pybind11::arg("polarity") = py::none());
}