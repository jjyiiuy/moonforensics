# 发布清单

这份清单用于确认 MoonForensics 在全新环境中可以复现、验证并打包发布。

## 发布前

- [ ] 确认工作区干净：`git status --short` 无输出。
- [ ] 确认提交作者和邮箱属于预期 GitHub 账号。
- [ ] 确认 `moon.mod` 中的版本、许可证、仓库 URL 和 `README.md` 正确。
- [ ] 确认 `README.md`、`docs/project-brief.md` 和 `samples/README.md` 的链接有效。
- [ ] 确认 `samples/incidents/` 中的时间、来源和输入保持固定，不依赖当前时间。

## 全新环境验证

在没有构建缓存的环境中执行：

```sh
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s latest
export PATH="$HOME/.moon/bin:$PATH"
moon version --all
moon fmt --check
moon check --deny-warn
moon test
moon info
git diff --exit-code -- '*.mbti'
```

验证文档中的 CLI 示例：

```sh
moon run cmd/main -- ingest '{"event_id":"evt-1","severity":"INFO"}'
moon run cmd/main -- analyze '{"event_id":"evt-1","severity":"INFO"}'
moon run cmd/main -- verify 'evidence bytes'
```

预期：测试全部通过，接口文件无未提交变化，三个命令均输出 `exit code 0`。

## 发布后

- [ ] 推送提交和标签到 GitHub。
- [ ] 确认 GitHub Actions 的 `Validate release-ready project` 通过。
- [ ] 从干净检出重新运行上面的验证命令。
- [ ] 在 GitHub Releases 中记录 MoonBit 工具链版本和提交号。
- [ ] 保留失败测试、摘要不匹配或接口变化的审计记录，不以强制跳过检查代替修复。
