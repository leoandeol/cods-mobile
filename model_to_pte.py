import torch
import torchvision, scipy  # all the hidden dependencies
from executorch.exir import to_edge_transform_and_lower
from executorch.backends.xnnpack.partition.xnnpack_partitioner import XnnpackPartitioner

model = torch.hub.load("facebookresearch/detr:main", "detr_resnet50", pretrained=True).eval()

# 1. Export your PyTorch model
example_inputs = (torch.randn(1, 3, 640, 640),)
exported_program = torch.export.export(model, example_inputs)

# 2. Optimize for target hardware (switch backends with one line)
program = to_edge_transform_and_lower(
    exported_program,
    partitioner=[
        XnnpackPartitioner()
    ],  # CPU | CoreMLPartitioner() for iOS | QnnPartitioner() for Qualcomm
).to_executorch()

# 3. Save for deployment
with open("model.pte", "wb") as f:
    f.write(program.buffer)

# Test locally via ExecuTorch runtime's pybind API (optional)
from executorch.runtime import Runtime

runtime = Runtime.get()
method = runtime.load_program("model.pte").load_method("forward")
outputs = method.execute([torch.randn(1, 3, 640, 640)])
print(outputs)
