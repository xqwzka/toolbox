# 工具箱

记账（简记账）+ 卡密（卡密管家）+ 网页（本地网页）合一的 App，全部本地运行，无账号、无同步。

## 切换

四个功能各保留原来的界面，不做改动。切换只走一处：主界面右下角的悬浮按钮，点开切换页，点卡片就切过去。

## 下载（视频解析）

新界面：粘贴分享链接或口令，解析后下载视频或单张图片到相册。抖音 / 小红书 / 快手 / B站走洛天，Instagram 走 socialdownloader，X 走 vxTwitter/fxTwitter，YouTube 走 Invidious（视频轨 + 音频轨本机合成，取最高画质）；也可填自建 cobalt 实例地址（最高画质）走 YouTube / X / Instagram。仅支持公开内容。

## 数据

- 记账和卡密共用一个 SwiftData 存储（LedgerRecord、CardCode）。
- 网页的导入文件存在 Documents，页面状态仍是重启重置（非持久 store + 本机回环 HTTP 服务）。
- 新包名 com.example.toolbox，SideStore 当全新 App：旧三个 App 里的数据不会自动迁移，确认新 App 没问题后再删旧 App；网页文件需重新导入。

## 构建

XcodeGen 项目（project.yml），push 到 main 自动触发 GitHub Actions 编出未签名 IPA，产物发到 builds 分支。
