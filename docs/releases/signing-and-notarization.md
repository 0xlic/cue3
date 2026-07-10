# macOS 签名与公证

`release.yml` 支持 Developer ID 签名与 Apple 公证，同时保留没有 Apple 凭据时的 ad-hoc 发布能力。

## GitHub Secrets

启用 Developer ID 发布需要同时配置以下五项 Secrets：

- `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64`：Developer ID Application `.p12` 文件的 Base64 内容。
- `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD`：导出 `.p12` 时使用的密码。
- `APPLE_NOTARY_API_KEY_BASE64`：App Store Connect API 私钥 `.p8` 文件的 Base64 内容。
- `APPLE_NOTARY_API_KEY_ID`：API Key ID。
- `APPLE_NOTARY_API_ISSUER_ID`：API Issuer ID。

二进制文件可使用以下命令转换为单行 Base64 内容：

```bash
base64 -i DeveloperIDApplication.p12
base64 -i AuthKey_XXXXXXXXXX.p8
```

不要把证书、私钥、密码或转换后的 Base64 内容提交到仓库。

## Workflow 行为

- 五项 Secrets 全部为空：使用原有 ad-hoc 签名，不执行公证。
- 五项 Secrets 全部存在：导入临时 keychain，使用 Developer ID 重新签名，提交 `notarytool`，完成 stapling 后再打包。
- 只配置部分 Secrets：workflow 立即失败，防止发布一个误以为已经签名或公证的产物。

GitHub Release 正文和产物内的 `RELEASE_NOTES.txt` 都会记录实际签名模式。

## 安全约束

- workflow 只在 runner 的临时目录中生成证书、私钥和 keychain。
- 发布结束或失败后都会删除临时 keychain。
- Apple 凭据轮换后，应同步更新全部相关 Secrets，并通过一次预发布 tag 验证签名、公证和 stapling。
- 不要在 workflow 日志中输出 Secret 内容、证书密码或 API 私钥。
