# DSH 部署模板 —— settings.yaml（通用骨架，不含任何私有模型/密钥配置）
#
# 说明：本模板只提供 DSH settings 的结构骨架，不预设任何具体 provider / 模型。
# 部署完成后，请进入 DSH Web UI 的设置页配置你自己的模型与 API Key；
# 或按下方结构自行填写 providers（密钥通过 apiKeyEnv 指定的环境变量读取，不落明文）。

# ---- LLM Provider 配置骨架（请自行填写）----
# llm-pi-ai:
#   providers:
#     # 示例：一个 provider 的结构
#     my-provider:
#       apiKeyEnv: MY_PROVIDER_API_KEY   # 密钥从该环境变量读取（不落明文）
#       models:
#         - id: my-model-id
#           name: My Model Name
#           contextWindow: 200000
#           maxTokens: 65536
#   ...
#
# agent-default-model:
#   provider: my-provider
#   model: my-model-id

# ---- 默认留空，等待用户自行配置 ----
{}
