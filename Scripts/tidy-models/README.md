# Tidy's open models

On devices without Apple Intelligence, Tidy groups tabs with [all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) (Apache-2.0) and names the groups with Mozilla's [smart-tab-topic](https://huggingface.co/Mozilla/smart-tab-topic) (MPL-2.0), Firefox's tab-group namer. Neither is published for Core ML, so Crest converts them and publishes the result as a release of this repository, as it does the Chromium engine. Nothing is bundled with the app: Crest downloads the files when the person turns Tidy on, checks each against the SHA-256 pinned in `TidyMethod.openModels`, and deletes them when Tidy is turned off. The two tokenizer files, `vocab.txt` and `tokenizer.json`, come straight from Hugging Face at pinned revisions.

## Converting

`convert.py` downloads both models at pinned revisions, writes `MiniLM.mlpackage`, `TopicEncoder.mlpackage` and `TopicDecoder.mlpackage`, and checks each against its original before writing it:

```
uv run Scripts/tidy-models/convert.py <out_dir>
```

## Publishing

A maintainer publishes a conversion as a new release, so the files an older Crest pins stay where they are:

```
Scripts/tidy-models/publish.sh <out_dir> pauljoda/Crest tidy-models-<n>
```

The script prints `SHA256SUMS`. Point `openModelsRelease` at the new tag, bump the method's `directoryName` so devices fetch the new files, and replace the pinned SHA-256 values in `TidyMethod.openModels`.
