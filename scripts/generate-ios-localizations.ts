import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

import {messages} from '../src/i18n.ts';

const appName = 'カロスキャン';
const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

const localeDefinitions = [
  {
    source: 'zh',
    bundle: 'zh-Hans',
    errorCameraDenied: '无法使用相机，请在“设置”中允许访问相机。',
    nativeMessages: {
      choosePhoto: '从照片中选择',
      analyzePhoto: '分析这张照片',
      cancel: '取消',
      openSettings: '打开设置',
      privacyPolicy: '隐私政策',
      support: '支持',
      consentNotice: '点击分析后，照片将发送至 Kalories 服务和 Gemini，仅用于本次食物分析。',
      errorRateLimited: '请求过于频繁，请稍后再试。',
      errorTimeout: '分析超时，请重试。',
    },
    cameraUsageDescription: '使用相机拍摄餐食，以估算卡路里和营养。',
  },
  {
    source: 'ja',
    bundle: 'ja',
    errorCameraDenied: 'カメラを利用できません。「設定」でカメラへのアクセスを許可してください。',
    nativeMessages: {
      choosePhoto: '写真から選ぶ',
      analyzePhoto: 'この写真を分析',
      cancel: 'キャンセル',
      openSettings: '設定を開く',
      privacyPolicy: 'プライバシーポリシー',
      support: 'サポート',
      consentNotice:
        '分析を開始すると、写真は今回の食事分析のために Kalories サービスと Gemini へ送信されます。',
      errorRateLimited: 'リクエストが多すぎます。少し待ってからお試しください。',
      errorTimeout: '分析がタイムアウトしました。もう一度お試しください。',
    },
    cameraUsageDescription: '食事を撮影し、カロリーと栄養を推定するためにカメラを使用します。',
  },
  {
    source: 'en',
    bundle: 'en',
    errorCameraDenied: 'Camera access is unavailable. Allow camera access in Settings.',
    nativeMessages: {
      choosePhoto: 'Choose a photo',
      analyzePhoto: 'Analyze this photo',
      cancel: 'Cancel',
      openSettings: 'Open Settings',
      privacyPolicy: 'Privacy Policy',
      support: 'Support',
      consentNotice:
        'When you analyze, the photo is sent to the Kalories service and Gemini only for this meal analysis.',
      errorRateLimited: 'Too many requests. Try again shortly.',
      errorTimeout: 'Analysis timed out. Please try again.',
    },
    cameraUsageDescription:
      'Camera access is used to photograph meals and estimate calories and nutrition.',
  },
] as const;

interface GeneratedFile {
  path: string;
  bytes: Buffer;
}

function escapeStringsValue(value: string): string {
  return value
    .replaceAll('\\', '\\\\')
    .replaceAll('"', '\\"')
    .replaceAll('\r\n', '\\n')
    .replaceAll('\r', '\\n')
    .replaceAll('\n', '\\n');
}

function renderStrings(values: Record<string, string>): Buffer {
  const contents = Object.keys(values)
    .sort()
    .map((key) => `"${escapeStringsValue(key)}" = "${escapeStringsValue(values[key])}";`)
    .join('\n');

  return Buffer.from(`${contents}\n`, 'utf8');
}

function generatedFiles(): GeneratedFile[] {
  return localeDefinitions.flatMap((locale) => {
    const directory = path.join(
      repositoryRoot,
      'ios',
      'Kalories',
      'Resources',
      `${locale.bundle}.lproj`,
    );
    const localizable = {
      ...messages[locale.source],
      ...locale.nativeMessages,
      appName,
      errorCameraDenied: locale.errorCameraDenied,
    };
    const infoPlist = {
      CFBundleDisplayName: appName,
      NSCameraUsageDescription: locale.cameraUsageDescription,
    };

    return [
      {
        path: path.join(directory, 'Localizable.strings'),
        bytes: renderStrings(localizable),
      },
      {
        path: path.join(directory, 'InfoPlist.strings'),
        bytes: renderStrings(infoPlist),
      },
    ];
  });
}

async function readExistingBytes(filePath: string): Promise<Buffer | null> {
  try {
    return await readFile(filePath);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
      return null;
    }
    throw error;
  }
}

async function checkGeneratedFiles(files: GeneratedFile[]): Promise<boolean> {
  const drift: string[] = [];

  for (const file of files) {
    const existing = await readExistingBytes(file.path);
    if (existing === null) {
      drift.push(`missing: ${path.relative(repositoryRoot, file.path)}`);
    } else if (!existing.equals(file.bytes)) {
      drift.push(`changed: ${path.relative(repositoryRoot, file.path)}`);
    }
  }

  if (drift.length > 0) {
    console.error('iOS localization resources are out of date:');
    for (const item of drift) {
      console.error(`- ${item}`);
    }
    return false;
  }

  console.log(`Verified ${files.length} generated iOS localization files.`);
  return true;
}

async function writeGeneratedFiles(files: GeneratedFile[]): Promise<void> {
  let written = 0;

  for (const file of files) {
    const existing = await readExistingBytes(file.path);
    if (existing?.equals(file.bytes)) {
      continue;
    }

    await mkdir(path.dirname(file.path), {recursive: true});
    await writeFile(file.path, file.bytes);
    written += 1;
  }

  console.log(`Generated ${files.length} iOS localization files (${written} written).`);
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const unknownFlags = args.filter((argument) => argument !== '--check');
  if (unknownFlags.length > 0) {
    console.error(`Unknown argument(s): ${unknownFlags.join(', ')}`);
    process.exitCode = 1;
    return;
  }

  const files = generatedFiles();
  if (args.includes('--check')) {
    if (!(await checkGeneratedFiles(files))) {
      process.exitCode = 1;
    }
    return;
  }

  await writeGeneratedFiles(files);
}

await main();
