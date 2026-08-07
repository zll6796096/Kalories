# Kalories

Kalories 是一个相机优先的餐食营养估算器。拍摄一餐后，应用会在同一张可滚动结果页上展示：

- 热量、蛋白质、碳水化合物、脂肪、膳食纤维、糖和钠的估算值；
- 每项营养素的高／适量／低／无法判断状态；
- 0–100 的估算健康分数、文字等级和最多两条改善建议；
- 照片识别、份量及各营养素的估算置信度。

模型只负责从照片估算食物事实、营养值和置信度；即使照片相同，模型估算也可能变化。健康分数、状态和建议由仓库中的确定性程序计算，采用日本优先、WHO 补充的一般成年人单餐启发式标准；相同的结构化营养估算输入会得到相同的本地评估结果。它不作医疗诊断，也不提供医疗建议。

界面支持日本語、中文和 English。已保存的语言选择优先；没有保存值时使用设备支持的 `ja`、`zh` 或 `en` 语言；设备语言不受支持时默认使用日语。

## 重要限制

照片结果是估算，不是营养测量、个性化每日摄入建议或医疗诊断。隐藏的油、酱汁、糖、盐、馅料以及实际份量都会显著影响结果；仅凭照片估算糖和钠通常置信度较低。当前评估面向一般成年人一餐，不考虑年龄、性别、体重、疾病、过敏、运动量或全天饮食。

## 隐私与支持页面

生产构建会把不依赖 JavaScript 的静态页面与应用一起提供：

- `/privacy/`：日文隐私政策，说明照片传输、第三方 AI、保存边界与撤回方式；
- `/support/`：日文优先、附简短中文和英文的使用帮助与公开 Issue 安全提示。

受控 TestFlight 仅限受邀的 18 岁以上测试者。公开 App Store 发布仍是独立且未完成的门禁。

TestFlight 分发前必须逐项确认 Cloud 项目使用 Gemini 付费服务，并保持开发者日志关闭、不向 Google 共享数据集；任一条件不满足时不得分发。付费服务条款规定提示、文件和响应不用于改进 Google 产品，但这不等于零保存：Google 默认滥用监控仍可能保存提示、上下文和输出（包括照片输入与分析输出）最长 55 天。当前没有证据证明该项目已获零数据保留（ZDR）批准，因此页面不作 ZDR 声明。

`npm run build`、本地页面测试或 `/privacy/` 与 `/support/` 返回 200，只能证明本地静态页面和组合服务可用；它们不能证明页面已部署，也不能证明 Cloud 项目的付费层级、开发者日志、数据集共享、ZDR 状态或第三方实际处理方式已经核验。相关依据见 [Gemini API 条款](https://ai.google.dev/gemini-api/terms)、[滥用监控与保存政策](https://ai.google.dev/gemini-api/docs/usage-policies)、[开发者日志政策](https://ai.google.dev/gemini-api/docs/logs-policy)和 [ZDR 说明](https://ai.google.dev/gemini-api/docs/zdr)。

## 本地运行

需要 Node.js、npm 和 `uv`。仓库通过 `.python-version` 将本地干净验证和 Vercel 部署统一到 Python 3.12。

```bash
npm install
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python -r requirements.txt
```

`requirements.in` 是人工维护的七项直接依赖输入；Vercel 识别的 `requirements.txt` 是 Python 3.12、Linux 目标下生成并验证的完整精确部署锁。部署和本地验收都必须安装 `requirements.txt`，不能绕过锁文件解析直接依赖。

在仓库根目录创建 `.env`，仅供后端读取：

```dotenv
GEMINI_API_KEY=your_backend_key
GEMINI_MODEL=gemini-3.6-flash
```

不要把真实密钥提交到 Git，也不要把它放进浏览器代码、`VITE_*` 变量或前端构建产物。

后端稳定默认模型是 `gemini-3.6-flash`。`GEMINI_MODEL` 是非密钥运行配置：
读取时会移除首尾空白，未配置或仅包含空白时回退到稳定默认值。更换模型前必须重新通过
完整 provider 响应契约测试，并在受控门禁中完成真实图片请求验证。针对当前 3.6
契约，`temperature`、`top_p` 和 `top_k` 等采样参数被有意省略；本地自动化不会发起
真实模型请求，也不能代替真实图片与 schema 行为验证。

分别启动 API 和界面：

```bash
.venv/bin/python -m uvicorn api.analyze:app --host 127.0.0.1 --port 8000
```

```bash
npm run dev
```

打开 [http://127.0.0.1:3000](http://127.0.0.1:3000)。Vite 会把 `/api` 请求代理到本地 8000 端口。

## Cloud Run

仓库根目录的多阶段 `Dockerfile` 会先构建前端，再由同一个 FastAPI
进程提供静态页面、`POST /api/analyze` 和 `GET /health`。README 不提供直接生产
部署命令；TestFlight 后端只能按照发布手册先创建 `--no-traffic` 候选，并逐项完成
不可变 revision、访问保护、隐私、配额、预算、真实请求与安全日志门禁。

未配置 `GEMINI_API_KEY` 时，页面仍可访问，但分析接口会以
`SERVICE_NOT_CONFIGURED` fail-closed。启用真实分析时，必须使用
Kalories 专用 Secret Manager secret，并同时配置外部身份／滥用防护、
速率限制、API 配额和预算告警；不要复用其他应用的 secret。

TestFlight 后端发布使用只读的
[`scripts/check-testflight-backend.sh`](scripts/check-testflight-backend.sh)
和精确的
[`docs/release/testflight-backend-runbook.md`](docs/release/testflight-backend-runbook.md)。
当前本地测试与构建成功不代表已部署；线上预检目前预期返回 `NO-GO`，任何 Cloud Run
候选部署、流量变更、密钥迁移或 TestFlight 操作都需要下一阶段的明确确认与独立证据。
当前服务的公网调用以及缺少可机器验证的应用层访问保护是硬 `NO-GO`；受邀 18+、
maxScale、进程内限流、provider RPD 和预算告警都是控损手段，不是访问控制。Task 6
和外部 TestFlight 必须等待单独的安全架构获用户确认、实现并通过验收。

## 图片与运行边界

API 接受 JPEG、PNG 和 WebP。前端会在上传前缩放并压缩照片；后端对解码后的图片执行 3 MiB 上限、格式签名、真实解码和像素数校验。超过边界、格式不受支持或内容损坏的图片会被拒绝。

生产环境还必须在外部平台配置身份／滥用防护、速率限制、API 配额和预算告警。进程内限流在无状态或多实例 serverless 环境中并不可靠，本仓库不会把它描述成生产级保护。

## 验证

```bash
npm test
npm run lint
npm run build
.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
.venv/bin/python -m compileall -q api lib tests
.venv/bin/python -c "import api.analyze, lib.nutrition, lib.rate_limit"
uv pip check --python .venv/bin/python
git diff --check
```

自动化测试和浏览器 UI 验收不能证明实际 Gemini 调用成功。只有在后端密钥存在、真实请求返回且服务日志与响应契约都确认后，才能把模型参与标记为已验证。

### 更新 Python 依赖

1. 只编辑人工输入 `requirements.in`，不要手工升级单个传递依赖。
2. 用 `uv pip compile --python 3.12 --python-platform x86_64-manylinux_2_28 --only-binary=:all: --no-annotate requirements.in -o requirements.txt` 重新生成 Vercel 部署锁；生成结果必须保持精确 `==` 版本且不含本地、URL 或 editable 依赖。
3. 用 `uv venv --python 3.12 .venv` 创建干净环境，再以 `uv pip install --python .venv/bin/python -r requirements.txt` 安装部署锁，运行后端测试、`compileall`、导入检查和 `uv pip check --python .venv/bin/python`，并用 `uv pip freeze --python .venv/bin/python` 与 `requirements.txt` 比较包版本。
4. 分别确认 CPython 3.12 的 macOS arm64 与 manylinux x86_64 wheel 可用；运行 `uvx pip-audit --no-deps --disable-pip -r requirements.txt`，结果无已知漏洞后再提交输入和部署锁。

## 参考依据

单餐分数是便于解释的产品启发式，不等同于官方膳食摄入基准。日本官方膳食摄入基准主要用于评估习惯性摄入，因此本应用不会把一张照片解释为全天或个人健康结论。

- [日本人の食事摂取基準（2025年版）](https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/kenkou_iryou/kenkou/eiyou/syokuji_kijyun.html)
- [日本人の食事摂取基準（2025年版）策定検討会報告書](https://www.mhlw.go.jp/stf/newpage_44138.html)
- [厚生劳动省：膳食摄入基准关注习惯性摄入](https://kennet.mhlw.go.jp/information/information/dictionary/food/ye-025)
- [农林水产省：食事バランスガイド](https://www.maff.go.jp/j/syokuiku/zissen_navi/balance/features.html)
- [WHO：Healthy diet](https://www.who.int/news-room/fact-sheets/detail/healthy-diet)
- [WHO：Sodium reduction](https://www.who.int/news-room/fact-sheets/detail/sodium-reduction)

## API 责任边界

`POST /api/analyze` 接收图片 data URI。响应中的 `food_names`、`portion_grams`、七项 `nutrients`、各项 `confidence` 及受控的 `assumption_keys` 是 AI 估算；`assessment.score`、`assessment.tier`、七项 `statuses` 和 `suggestion_keys` 是本地确定性代码生成。前端会逐项显示置信度并将四种已知假设本地化，不会暴露未知内部键。缺失值返回 `null`，前端显示为 `—`，不会用 `0` 冒充未知数据。

为了避免不完整营养结构产生虚假的高分，只有热量、蛋白质、碳水化合物、脂肪全部存在，三大营养素的能量分母为正，且总体置信度为中或高时才返回分数；否则分数为 `null`，结论为无法判断。
