# AI 服务商配置（不内置密钥）

安装包只内置服务商地址和模型名称，不包含任何 API Key，也不再读取编译参数中的密钥。

- DeepSeek：`https://api.deepseek.com`，文本模型 `deepseek-flash`。
- 智谱 GLM：`https://open.bigmodel.cn/api/paas/v4`，语音模型 `glm-asr-2512`。

首次安装后，在“我的 → 智能记账 → AI小助手 → 服务商管理”分别填写自己的 Key。
能力绑定默认使用 DeepSeek 处理文本、智谱处理语音和图片。
覆盖安装保留设备上已经保存的配置、Key 和能力绑定。

构建不需要密钥文件：

```sh
flutter build apk --debug --flavor dev --target-platform android-arm64,android-x64
```

本机 `E:\BeeCountDev\start-beecount.ps1` 也使用不带密钥的构建命令。
此前已经生成或发送的旧 APK 不会被这次源码修改改变，分发时请使用新的无内置 Key 版本。
