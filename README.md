# 工具箱

记账（简记账）+ 卡密（卡密管家）+ 网页（本地网页）合一的 App，全部本地运行，无账号、无同步。

## 切换

三个功能各保留原来的界面，不做改动。切换只走一处：主界面右下角的悬浮按钮，点开切换页，点卡片就切过去。

## 数据

- 记账和卡密共用一个 SwiftData 存储（LedgerRecord、CardCode）。
- 网页的导入文件存在 Documents，页面状态仍是重启重置（非持久 store + 本机回环 HTTP 服务）。
- 新包名 com.example.toolbox，SideStore 当全新 App：旧三个 App 里的数据不会自动迁移，确认新 App 没问题后再删旧 App；网页文件需重新导入。

## 构建

XcodeGen 项目（project.yml），push 到 main 自动触发 GitHub Actions 编出未签名 IPA，产物发到 builds 分支。
