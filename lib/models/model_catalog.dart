/// Definitions for the downloadable offline model files.
///
/// Each [ModelSpec] is a set of plain files downloaded into its install
/// directory — no archive extraction on-device (avoids big memory spikes).
/// [ModelSpec.hfRepo]/[hfIncludePrefix] additionally pull every file under
/// a prefix from a HuggingFace repo listing at download time.
library;

enum ModelKind { llm, stt, tts, avatar }

class ModelFileItem {
  final String url;
  final String relPath;
  const ModelFileItem(this.url, this.relPath);
}

class ModelSpec {
  final ModelKind kind;
  final String id;
  final String name;
  final String description;

  /// Display-only size estimate.
  final int sizeBytes;

  /// Primary payload file name (LLM .gguf / avatar .glb), '' if not used.
  final String fileName;

  /// Explicit files to download.
  final List<ModelFileItem> files;

  /// Optional HuggingFace repo ('org/name') whose sibling list is fetched at
  /// download time; only files under [hfIncludePrefix] are downloaded.
  final String? hfRepo;
  final String? hfIncludePrefix;

  const ModelSpec({
    required this.kind,
    required this.id,
    required this.name,
    required this.description,
    required this.sizeBytes,
    this.fileName = '',
    this.files = const [],
    this.hfRepo,
    this.hfIncludePrefix,
  });

  String get sizeLabel {
    if (sizeBytes >= 1 << 30) {
      return '${(sizeBytes / (1 << 30)).toStringAsFixed(1)} GB';
    }
    return '${(sizeBytes / (1 << 20)).toStringAsFixed(0)} MB';
  }
}

const _hf = 'https://huggingface.co';

const kLlmModels = <ModelSpec>[
  ModelSpec(
    kind: ModelKind.llm,
    id: 'qwen25-0.5b-q4km',
    name: 'Qwen2.5 0.5B Instruct',
    description: 'Fastest. Good on low-RAM phones.',
    sizeBytes: 397000000,
    fileName: 'qwen25-0.5b-instruct-q4km.gguf',
    files: [
      ModelFileItem(
        '$_hf/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf',
        'qwen25-0.5b-instruct-q4km.gguf',
      ),
    ],
  ),
  ModelSpec(
    kind: ModelKind.llm,
    id: 'llama32-1b-q4km',
    name: 'Llama 3.2 1B Instruct',
    description: 'Smarter replies, needs ~2 GB free RAM.',
    sizeBytes: 808000000,
    fileName: 'llama32-1b-instruct-q4km.gguf',
    files: [
      ModelFileItem(
        '$_hf/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
        'llama32-1b-instruct-q4km.gguf',
      ),
    ],
  ),
  ModelSpec(
    kind: ModelKind.llm,
    id: 'smollm2-360m-q8',
    name: 'SmolLM2 360M Instruct',
    description: 'Smallest and fastest, simplest answers.',
    sizeBytes: 386000000,
    fileName: 'smollm2-360m-instruct-q8.gguf',
    files: [
      ModelFileItem(
        '$_hf/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q8_0.gguf',
        'smollm2-360m-instruct-q8.gguf',
      ),
    ],
  ),
];

const kSttModels = <ModelSpec>[
  ModelSpec(
    kind: ModelKind.stt,
    id: 'whisper-tiny-en',
    name: 'Whisper Tiny (English)',
    description: 'English only — fastest.',
    sizeBytes: 110000000,
    files: [
      ModelFileItem(
        '$_hf/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main/tiny.en-encoder.int8.onnx',
        'tiny.en-encoder.int8.onnx',
      ),
      ModelFileItem(
        '$_hf/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main/tiny.en-decoder.int8.onnx',
        'tiny.en-decoder.int8.onnx',
      ),
      ModelFileItem(
        '$_hf/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main/tiny.en-tokens.txt',
        'tiny.en-tokens.txt',
      ),
    ],
  ),
  ModelSpec(
    kind: ModelKind.stt,
    id: 'whisper-tiny-multi',
    name: 'Whisper Tiny (Multilingual)',
    description: 'Understands Tamil, English and 90+ languages.',
    sizeBytes: 110000000,
    files: [
      ModelFileItem(
        '$_hf/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-encoder.int8.onnx',
        'tiny-encoder.int8.onnx',
      ),
      ModelFileItem(
        '$_hf/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-decoder.int8.onnx',
        'tiny-decoder.int8.onnx',
      ),
      ModelFileItem(
        '$_hf/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-tokens.txt',
        'tiny-tokens.txt',
      ),
    ],
  ),
];

const kTtsModels = <ModelSpec>[
  ModelSpec(
    kind: ModelKind.tts,
    id: 'piper-lessac-low',
    name: 'Piper en_US Lessac',
    description: 'sherpa-onnx VITS voice, US English.',
    sizeBytes: 65000000,
    files: [
      ModelFileItem(
        '$_hf/csukuangfj/vits-piper-en_US-lessac-low/resolve/main/en_US-lessac-low.onnx',
        'en_US-lessac-low.onnx',
      ),
      ModelFileItem(
        '$_hf/csukuangfj/vits-piper-en_US-lessac-low/resolve/main/en_US-lessac-low.onnx.json',
        'en_US-lessac-low.onnx.json',
      ),
      ModelFileItem(
        '$_hf/csukuangfj/vits-piper-en_US-lessac-low/resolve/main/tokens.txt',
        'tokens.txt',
      ),
    ],
    hfRepo: 'csukuangfj/vits-piper-en_US-lessac-low',
    hfIncludePrefix: 'espeak-ng-data/',
  ),
  ModelSpec(
    kind: ModelKind.tts,
    id: 'piper-ta-rasa-female',
    name: 'Piper தமிழ் Rasa (female)',
    description: 'Tamil voice. tokens.txt is generated at install.',
    sizeBytes: 110000000,
    files: [
      ModelFileItem(
        '$_hf/tinisoft/piper-ta_IN-rasa_female-medium/resolve/main/ta_IN-rasa_female-medium.onnx',
        'ta_IN-rasa_female-medium.onnx',
      ),
      ModelFileItem(
        '$_hf/tinisoft/piper-ta_IN-rasa_female-medium/resolve/main/ta_IN-rasa_female-medium.onnx.json',
        'ta_IN-rasa_female-medium.onnx.json',
      ),
    ],
    // espeak-ng-data is shared across Piper voices — reuse the same mirror.
    hfRepo: 'csukuangfj/vits-piper-en_US-lessac-low',
    hfIncludePrefix: 'espeak-ng-data/',
  ),
  ModelSpec(
    kind: ModelKind.tts,
    id: 'piper-ta-rasa-male',
    name: 'Piper தமிழ் Rasa (male)',
    description: 'Tamil voice. tokens.txt is generated at install.',
    sizeBytes: 110000000,
    files: [
      ModelFileItem(
        '$_hf/tinisoft/piper-ta_IN-rasa_male-medium/resolve/main/ta_IN-rasa_male-medium.onnx',
        'ta_IN-rasa_male-medium.onnx',
      ),
      ModelFileItem(
        '$_hf/tinisoft/piper-ta_IN-rasa_male-medium/resolve/main/ta_IN-rasa_male-medium.onnx.json',
        'ta_IN-rasa_male-medium.onnx.json',
      ),
    ],
    hfRepo: 'csukuangfj/vits-piper-en_US-lessac-low',
    hfIncludePrefix: 'espeak-ng-data/',
  ),
];

const kAvatarModels = <ModelSpec>[
  ModelSpec(
    kind: ModelKind.avatar,
    id: 'facecap',
    name: 'Avatar head (lip sync)',
    description: 'Head model with ARKit blend shapes — real lip sync.',
    sizeBytes: 340000,
    fileName: 'facecap.glb',
    files: [
      ModelFileItem(
        'https://raw.githubusercontent.com/mrdoob/three.js/dev/examples/models/gltf/facecap.glb',
        'facecap.glb',
      ),
    ],
  ),
  ModelSpec(
    kind: ModelKind.avatar,
    id: 'robot',
    name: 'Robot (full body)',
    description: 'Animated robot body, simpler mouth sync.',
    sizeBytes: 4500000,
    fileName: 'robot.glb',
    files: [
      ModelFileItem(
        'https://raw.githubusercontent.com/mrdoob/three.js/dev/examples/models/gltf/RobotExpressive/RobotExpressive.glb',
        'robot.glb',
      ),
    ],
  ),
  ModelSpec(
    kind: ModelKind.avatar,
    id: 'xbot',
    name: 'Xbot (humanoid)',
    description: 'Animated humanoid character.',
    sizeBytes: 7500000,
    fileName: 'xbot.glb',
    files: [
      ModelFileItem(
        'https://raw.githubusercontent.com/mrdoob/three.js/dev/examples/models/gltf/Xbot.glb',
        'xbot.glb',
      ),
    ],
  ),
  ModelSpec(
    kind: ModelKind.avatar,
    id: 'michelle',
    name: 'Michelle (humanoid)',
    description: 'Animated human character, realistic look.',
    sizeBytes: 5500000,
    fileName: 'michelle.glb',
    files: [
      ModelFileItem(
        'https://raw.githubusercontent.com/mrdoob/three.js/dev/examples/models/gltf/Michelle.glb',
        'michelle.glb',
      ),
    ],
  ),
];

/// Pseudo-spec for a user-imported .glb file (not downloadable).
const kCustomAvatarSpec = ModelSpec(
  kind: ModelKind.avatar,
  id: 'custom',
  name: 'Custom GLB',
  description: 'Your own .glb avatar file.',
  sizeBytes: 0,
  fileName: 'avatar.glb',
);

List<ModelSpec> specsFor(ModelKind kind) => switch (kind) {
      ModelKind.llm => kLlmModels,
      ModelKind.stt => kSttModels,
      ModelKind.tts => kTtsModels,
      ModelKind.avatar => kAvatarModels,
    };

ModelSpec specById(ModelKind kind, String id) =>
    specsFor(kind).firstWhere((s) => s.id == id,
        orElse: () => specsFor(kind).first);
