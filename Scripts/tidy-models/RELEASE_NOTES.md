The open models Crest's Tidy downloads on devices without Apple Intelligence, converted to Core ML with int8 weights by `Scripts/tidy-models/convert.py`. Crest downloads these files only when the person turns Tidy on, checks each against the SHA-256 it pins, and deletes them when Tidy is turned off.

- `MiniLM-*`: [all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) by the sentence-transformers authors, converted and quantized. Apache License 2.0, in `MiniLM-LICENSE.txt`.

- `TopicEncoder-*` and `TopicDecoder-*`: [smart-tab-topic](https://huggingface.co/Mozilla/smart-tab-topic) by Mozilla, Firefox's tab-group namer, rebuilt from its ONNX weights, converted and quantized. Mozilla Public License 2.0, in `smart-tab-topic-LICENSE.txt`; the conversion's source is `Scripts/tidy-models/convert.py` in Crest's repository.

Each `<Package>-<file>` asset is one file of `<Package>.mlpackage`: `Manifest.json`, `Data/com.apple.CoreML/model.mlmodel` and `Data/com.apple.CoreML/weights/weight.bin`.
