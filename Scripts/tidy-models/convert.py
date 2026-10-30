# /// script
# requires-python = ">=3.11,<3.13"
# dependencies = ["coremltools==8.3.0", "torch==2.5.1", "transformers==4.46.3", "sentencepiece", "onnx", "onnxruntime", "huggingface_hub", "numpy<2.2", "scikit-learn"]
# ///
"""Convert the open models Tidy runs on devices without Apple Intelligence to Core ML, with int8 weights.

- MiniLM.mlpackage: sentence-transformers/all-MiniLM-L6-v2 (Apache-2.0), mean-pooled and unit length, as
  sentence-transformers returns it. Per-tensor int8 weights.
- TopicEncoder.mlpackage and TopicDecoder.mlpackage: Mozilla/smart-tab-topic (MPL-2.0), Firefox's tab-group namer.
  The repository ships only ONNX weights, so they are first loaded into a PyTorch T5 and checked against onnxruntime.
  The decoder has no cache: encoder states and the ids so far give the next token's logits. Per-block int8 weights.

Each converted model is checked against its original before it is written. The forward pass of T5 is written out here
rather than traced from transformers, so its masks and position biases are plain tables: transformers multiplies
masks by float32's minimum, which is -inf in fp16. `bucket` is adapted from `T5Attention._relative_position_bucket`
in Hugging Face transformers (Copyright 2018 The Mesh TensorFlow Authors, The T5 Authors and The HuggingFace Inc.
team), under the Apache License, Version 2.0: https://www.apache.org/licenses/LICENSE-2.0

Usage: uv run Scripts/tidy-models/convert.py <out_dir>"""
import math, os, sys
import coremltools as ct
import numpy as np
import onnx
import onnxruntime as ort
import torch
from huggingface_hub import hf_hub_download
from onnx import numpy_helper
from transformers import AutoModel, AutoTokenizer, T5Config, T5ForConditionalGeneration

MINILM, MINILM_REVISION = "sentence-transformers/all-MiniLM-L6-v2", "1110a243fdf4706b3f48f1d95db1a4f5529b4d41"
TOPIC, TOPIC_REVISION = "Mozilla/smart-tab-topic", "91a6ebc0318de964b0e318c89ba01514746aadb8"
MAX_TITLE, MAX_PROMPT = 128, 256  # the longest inputs the converted models accept, in tokens
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
opt = ct.optimize.coreml


def quantized(model, **granularity):
    return opt.linear_quantize_weights(model, opt.OptimizationConfig(
        global_config=opt.OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8", **granularity)))


def convert(traced, inputs, output):
    return ct.convert(traced, inputs=inputs, outputs=[ct.TensorType(output)], convert_to="mlprogram",
                      minimum_deployment_target=ct.target.macOS15)


# MiniLM

tokenizer = AutoTokenizer.from_pretrained(MINILM, revision=MINILM_REVISION)
bert = AutoModel.from_pretrained(MINILM, revision=MINILM_REVISION, attn_implementation="eager").eval()


class Embed(torch.nn.Module):
    """Mean of the token vectors under the mask, unit length."""

    def __init__(self):
        super().__init__()
        self.bert = bert

    def forward(self, input_ids, attention_mask):
        # BERT's own mask multiplies by float32's minimum, which is -inf in fp16 and turns 0 * -inf into NaN.
        additive = (1.0 - attention_mask[:, None, None, :].float()) * -1e4
        hidden = self.bert.encoder(self.bert.embeddings(input_ids=input_ids), attention_mask=additive)[0]
        mask = attention_mask.unsqueeze(-1).to(hidden.dtype)
        mean = (hidden * mask).sum(1) / mask.sum(1).clamp(min=1e-9)
        return torch.nn.functional.normalize(mean, dim=-1)


embed = Embed().eval()
example = tokenizer(["an example title"], return_tensors="pt")
length = ct.RangeDim(lower_bound=1, upper_bound=MAX_TITLE, default=16)
minilm = quantized(convert(
    torch.jit.trace(embed, (example["input_ids"], example["attention_mask"])),
    [ct.TensorType("input_ids", shape=(1, length), dtype=np.int32),
     ct.TensorType("attention_mask", shape=(1, length), dtype=np.int32)], "embedding"))
titles = ["Pad thai recipe", "Docker Compose overview", "Best road bikes under $1,000", "Hiking in Yosemite",
          "Malolactic fermentation in winemaking", "PyTorch tutorials: training a classifier"]
with torch.no_grad():
    for title in titles:
        encoded = tokenizer([title], return_tensors="pt")
        expected = embed(encoded["input_ids"], encoded["attention_mask"])[0].numpy()
        got = minilm.predict({k: encoded[k].numpy().astype(np.int32) for k in ("input_ids", "attention_mask")})
        vector = np.array(got["embedding"]).reshape(-1)
        cosine = float(expected @ vector / np.linalg.norm(vector))
        assert cosine > 0.99, f"MiniLM differs from the original on {title!r}: cosine {cosine:.4f}"
minilm.save(f"{out}/MiniLM.mlpackage")
print("MiniLM converted and checked")

# smart-tab-topic, rebuilt from its ONNX weights

config = T5Config.from_pretrained(TOPIC, revision=TOPIC_REVISION)
hf = T5ForConditionalGeneration(config).eval()
expected_state = hf.state_dict()
state = {}
onnx_files = {stack: hf_hub_download(TOPIC, f"onnx/{stack}_model.onnx", revision=TOPIC_REVISION)
              for stack in ("encoder", "decoder")}
for stack, path in onnx_files.items():
    graph = onnx.load(path).graph
    initializers = {t.name: numpy_helper.to_array(t) for t in graph.initializer}
    for name, array in initializers.items():
        if name.startswith(("onnx::", "/")):
            continue
        key = name if name.startswith(("shared.", "lm_head.", "encoder.", "decoder.")) else f"{stack}.{name}"
        if key not in expected_state and key.replace(f"{stack}.embed_tokens", "shared") in expected_state:
            key = key.replace(f"{stack}.embed_tokens", "shared")
        state[key] = torch.from_numpy(array.copy())
    # The anonymous MatMul weights map by the module path in their node's name.
    for node in graph.node:
        weights = [i for i in node.input if i.startswith("onnx::MatMul")]
        if node.op_type != "MatMul" or not weights:
            continue
        parts = node.name.strip("/").split("/")[:-1]
        module = ".".join(parts[1:] if parts[0] == stack else parts)
        key = module + ".weight" if module.startswith("lm_head") else f"{stack}.{module}.weight"
        state[key] = torch.from_numpy(initializers[weights[0]].T.copy())
tied = {"encoder.embed_tokens.weight", "decoder.embed_tokens.weight"}  # both are `shared`
missing = set(expected_state) - set(state) - tied - ({"lm_head.weight"} if config.tie_word_embeddings else set())
assert not missing and not set(state) - set(expected_state), f"rebuild mismatch: {sorted(missing)}"
hf.load_state_dict(state, strict=False)
topic_tokenizer = AutoTokenizer.from_pretrained(TOPIC, revision=TOPIC_REVISION)
onnx_encoder, onnx_decoder = (ort.InferenceSession(onnx_files[s]) for s in ("encoder", "decoder"))
prompt = "Topic from keywords: lisbon,tram,hotel. titles: \nLisbon trams guide\nHotels in Alfama\nTAP Air Portugal flights"
with torch.no_grad():
    encoded = topic_tokenizer(prompt, return_tensors="np")
    ids = np.array([[0, 3, 5, 7]], dtype=np.int64)
    hidden = onnx_encoder.run(None, {"input_ids": encoded["input_ids"], "attention_mask": encoded["attention_mask"]})[0]
    onnx_logits = onnx_decoder.run(None, {"input_ids": ids, "encoder_hidden_states": hidden,
                                          "encoder_attention_mask": encoded["attention_mask"]})[0]
    torch_logits = hf(input_ids=torch.from_numpy(encoded["input_ids"]), decoder_input_ids=torch.from_numpy(ids)).logits
    assert np.abs(onnx_logits - torch_logits.numpy()).max() < 1e-3, "rebuilt T5 differs from the ONNX model"


def bucket(relative, bidirectional, buckets=config.relative_attention_num_buckets,
           distance=config.relative_attention_max_distance):
    result = torch.zeros_like(relative)
    if bidirectional:
        buckets //= 2
        result += (relative > 0).long() * buckets
        relative = relative.abs()
    else:
        relative = -torch.clamp(relative, max=0)
    exact = buckets // 2
    large = exact + (torch.log(relative.clamp(min=1).float() / exact) / math.log(distance / exact)
                     * (buckets - exact)).long()
    return result + torch.where(relative < exact, relative, large.clamp(max=buckets - 1))


def bias_table(attention, bidirectional, causal):
    position = torch.arange(MAX_PROMPT)
    table = attention.relative_attention_bias(bucket(position[None, :] - position[:, None], bidirectional))
    table = table.permute(2, 0, 1).unsqueeze(0)  # 1, heads, query, key
    if causal:
        table = table + torch.triu(torch.full((MAX_PROMPT, MAX_PROMPT), -1e4), diagonal=1)
    return table.detach()


def norm(layer, x):
    return layer.weight * (x * torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + layer.variance_epsilon))


def attend(attention, x, memory, bias):
    def heads(t):
        return t.view(1, -1, config.num_heads, config.d_kv).transpose(1, 2)

    q, k, v = heads(attention.q(x)), heads(attention.k(memory)), heads(attention.v(memory))
    scores = torch.matmul(q, k.transpose(2, 3))  # T5 does not scale by sqrt(d_kv)
    if bias is not None:
        scores = scores + bias
    context = torch.matmul(torch.softmax(scores.float(), dim=-1), v).transpose(1, 2)
    return attention.o(context.reshape(1, -1, config.num_heads * config.d_kv))


class Encoder(torch.nn.Module):
    """Prompt ids to hidden states. One prompt at a time, so there is no padding and no mask."""

    def __init__(self):
        super().__init__()
        self.stack = hf.encoder
        self.register_buffer("bias", bias_table(hf.encoder.block[0].layer[0].SelfAttention, True, False))

    def forward(self, input_ids):
        n = input_ids.shape[1]
        x = self.stack.embed_tokens(input_ids)
        for block in self.stack.block:
            attention, feed_forward = block.layer
            h = norm(attention.layer_norm, x)
            x = x + attend(attention.SelfAttention, h, h, self.bias[:, :, :n, :n])
            dense = feed_forward.DenseReluDense
            x = x + dense.wo(torch.relu(dense.wi(norm(feed_forward.layer_norm, x))))
        return norm(self.stack.final_layer_norm, x)


class Decoder(torch.nn.Module):
    """Encoder states and the ids decoded so far to the next token's logits."""

    def __init__(self):
        super().__init__()
        self.stack, self.shared = hf.decoder, hf.shared
        self.register_buffer("bias", bias_table(hf.decoder.block[0].layer[0].SelfAttention, False, True))

    def forward(self, decoder_ids, encoder_states):
        n = decoder_ids.shape[1]
        x = self.stack.embed_tokens(decoder_ids)
        for block in self.stack.block:
            attention, cross, feed_forward = block.layer
            h = norm(attention.layer_norm, x)
            x = x + attend(attention.SelfAttention, h, h, self.bias[:, :, :n, :n])
            x = x + attend(cross.EncDecAttention, norm(cross.layer_norm, x), encoder_states, None)
            dense = feed_forward.DenseReluDense
            x = x + dense.wo(torch.relu(dense.wi(norm(feed_forward.layer_norm, x))))
        last = norm(self.stack.final_layer_norm, x)[:, -1, :] * config.d_model ** -0.5  # tied output embedding
        return torch.matmul(last, self.shared.weight.T)


encoder, decoder = Encoder().eval(), Decoder().eval()
prompt_ids = torch.from_numpy(topic_tokenizer(prompt, return_tensors="np")["input_ids"])
decoded_ids = torch.tensor([[0, 3, 5, 7]])
with torch.no_grad():
    states = encoder(prompt_ids)
    reference = hf(input_ids=prompt_ids, decoder_input_ids=decoded_ids)
    assert (states - reference.encoder_last_hidden_state).abs().max() < 1e-3, "written-out encoder differs"
    assert (decoder(decoded_ids, states) - reference.logits[:, -1]).abs().max() < 1e-2, "written-out decoder differs"
    traced_encoder = torch.jit.trace(encoder, (prompt_ids,))
    traced_decoder = torch.jit.trace(decoder, (decoded_ids, states))

prompt_length = ct.RangeDim(lower_bound=1, upper_bound=MAX_PROMPT, default=32)
decoded_length = ct.RangeDim(lower_bound=1, upper_bound=MAX_PROMPT, default=4)
per_block = {"granularity": "per_block", "block_size": 32}
topic_encoder = quantized(convert(
    traced_encoder, [ct.TensorType("input_ids", shape=(1, prompt_length), dtype=np.int32)], "encoder_states"),
    **per_block)
topic_decoder = quantized(convert(
    traced_decoder, [ct.TensorType("decoder_ids", shape=(1, decoded_length), dtype=np.int32),
                     ct.TensorType("encoder_states", shape=(1, prompt_length, config.d_model), dtype=np.float32)],
    "logits"), **per_block)


def name(text):
    """Greedy decoding, as Crest runs it."""
    ids = topic_tokenizer(text, return_tensors="np")["input_ids"].astype(np.int32)
    hidden = np.array(topic_encoder.predict({"input_ids": ids})["encoder_states"]).astype(np.float32)
    decoded = [0]
    for _ in range(12):
        logits = topic_decoder.predict({"decoder_ids": np.array([decoded], dtype=np.int32), "encoder_states": hidden})
        token = int(np.array(logits["logits"]).reshape(-1).argmax())
        if token == topic_tokenizer.eos_token_id:
            break
        decoded.append(token)
    return topic_tokenizer.decode(decoded[1:], skip_special_tokens=True).strip()


topic = name(prompt)
assert topic, "the converted namer gave no name"
print(f"smart-tab-topic converted and checked; it names the Lisbon prompt {topic!r}")
topic_encoder.save(f"{out}/TopicEncoder.mlpackage")
topic_decoder.save(f"{out}/TopicDecoder.mlpackage")
