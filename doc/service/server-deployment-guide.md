# xs-blog 服务器部署指南

## 1. 你的思路对不对

你的思路是对的，而且对于当前这个项目阶段来说，是一条合理的演进路线。

也就是：

1. 服务器上通过 Git 拉取主仓库。
2. 同时拉取子模块。
3. 创建生产环境 `.env`。
4. 运行顶层 `docker compose up -d --build`。
5. 以后通过 `git pull` 和 `docker compose up -d --build` 完成更新。

这套方式已经比“复制粘贴源码到服务器”规范很多，至少具备这些优点：

- 代码来源可追溯。
- 部署步骤可重复。
- 子模块版本可被主仓库锁定。
- 后续回滚也更容易。

但是如果要让它真正适合服务器长期运行，你还需要补上几个关键环节。

## 2. 服务器部署不只是 clone + up

除了 `git clone`、`.env`、`docker compose up` 之外，通常还要处理以下事项：

- 安装 Docker 和 Compose 插件。
- 使用 `--recurse-submodules` 拉取子模块。
- 准备生产环境 `.env`，且不要提交到仓库。
- 开放和管理服务器端口。
- 配置域名、HTTPS 和反向代理。
- 规划数据库数据卷和备份。
- 规划日志和更新策略。
- 设计“更新失败如何回滚”。

所以，严格说：

**不是只要 clone 后跑 compose 就万事大吉，而是 clone + 环境准备 + 容器编排 + 运维约束，才算完整部署。**

## 3. 适合你当前项目的推荐部署方式

对你现在这套仓库，我建议分两阶段看。

### 第一阶段：源码直部署

这是你现在最适合采用的方式。

服务器上直接：

- 拉取 `xs-blog-base`
- 更新子模块
- 准备 `.env`
- 执行 compose 重建

优点：

- 简单直接。
- 不需要先搭镜像仓库。
- 适合个人项目和早期阶段。

缺点：

- 服务器需要具备构建能力。
- 更新时会在服务器现场构建镜像。
- 如果 Node/Python 依赖构建慢，部署耗时会更长。

### 第二阶段：CI 构建镜像，服务器只负责拉取和启动

这是更工程化的方案。

流程变成：

1. 本地或 GitHub Actions 构建 `web`、`server`、`db` 镜像。
2. 推送到镜像仓库。
3. 服务器上只执行：

```bash
docker compose pull
docker compose up -d
```

优点：

- 部署更快。
- 服务器更干净。
- 构建和运行职责分离。
- 更适合持续交付。

缺点：

- 你需要额外维护镜像仓库和 CI。

## 4. 对你当前阶段的明确建议

如果你现在还没有镜像仓库，也还没有 CI，那就不要一开始把复杂度拉太高。

**最适合你的路径是：先把“源码直部署”做规范，再逐步升级到“镜像部署”。**

补充一点：

- 开发环境和生产环境不要共用同一套运行方式。
- 开发环境可以使用 Vite dev server 和后端热重载。
- 生产环境应使用打包后的前端静态资源和稳定的 API 进程。

对当前仓库而言：

- `docker-compose.yml` 作为生产基线。
- `docker-compose.dev.yml` 作为开发覆盖层。

也就是说，当前推荐方案是：

- 用 Git 管理部署来源。
- 用子模块管理 server、web、db 版本。
- 用服务器 `.env` 管理生产环境变量。
- 用顶层 compose 作为唯一启动入口。
- 用一个固定更新脚本完成更新和重启。

这已经足够比复制粘贴优雅很多。

## 5. 服务器首次部署的标准步骤

以下假设你的服务器是 Linux。

### 5.1 安装基础环境

至少需要：

- Git
- Docker
- Docker Compose 插件

你可以先验证：

```bash
git --version
docker --version
docker compose version
```

### 5.2 首次拉取代码

建议使用子模块递归拉取：

```bash
git clone --recurse-submodules <your-base-repo-url>
cd xs-blog-base
```

如果仓库已经 clone 过，但没拉子模块：

```bash
git submodule update --init --recursive
```

### 5.3 创建生产环境变量

建议：

- 以仓库根目录的 `.env.example` 为模板。
- 在服务器创建 `.env`。
- 这个 `.env` 不要提交到 Git。

至少要认真修改这些值：

- `POSTGRES_PASSWORD`
- `DATABASE_URL`
- `REDIS_PASSWORD`
- `REDIS_URL`
- `SECRET_KEY`
- `ALLOWED_ORIGINS`
- 邮件配置

如果你的站点域名是 `https://blog.example.com`，那么 `ALLOWED_ORIGINS` 至少要包含真实前端域名。

### 5.4 启动服务

对于服务器或 1Panel 这类面板编排环境，建议把数据库迁移作为独立步骤执行，不要把一次性 `migrate` 容器放进长期运行的生产编排里。

首次部署或本次发版包含数据库变更时，先执行：

```bash
docker compose run --rm api alembic upgrade head
```

如果接入的是已有历史库，且还没有 `alembic_version`，先执行：

```bash
docker compose run --rm api alembic stamp 20260311_0001
docker compose run --rm api alembic upgrade head
```

然后再启动长期运行服务：

在主仓库根目录执行：

```bash
docker compose up -d --build
```

### 5.5 检查服务状态

```bash
docker compose ps
docker compose logs -f api
docker compose logs -f web
```

## 6. 后续更新的推荐方式

你想要的这个目标是正确的：

**服务器上执行 `git pull` 之后，再执行一次编排命令，就完成部署。**

但因为你用了子模块，正确流程不是只执行 `git pull`，而是：

```bash
git pull
git submodule update --init --recursive
docker compose run --rm api alembic upgrade head
docker compose up -d --build
```

如果你希望更稳一点，可以加上镜像清理：

```bash
docker image prune -f
```

所以你后续的标准更新流程建议固定成：

```bash
git pull
git submodule update --init --recursive
docker compose run --rm api alembic upgrade head
docker compose up -d --build
docker image prune -f
```

## 7. 为什么你不能只写 git pull

因为你现在不是单仓库，而是主仓库 + 子模块。

主仓库更新后，子模块引用的 commit 也可能变化。如果你只执行 `git pull`，但没有同步子模块，就会出现：

- base 仓库引用的是新版本子模块
- 服务器本地子模块代码却还是旧的

这会导致部署结果和你预期不一致。

所以对子模块项目来说，`git submodule update --init --recursive` 是部署流程的一部分，不是可选项。

## 8. 服务器上还建议做的处理

这里是你现在最容易忽略，但实际上很重要的部分。

### 8.1 反向代理和 HTTPS

虽然你当前 `web` 暴露了 `80`，`api` 暴露了 `8000`，但在服务器上更推荐：

- 对外只开放 `80` 和 `443`
- `8000` 不直接暴露公网，或者只在内网使用
- 使用 Nginx 或 Caddy 统一处理 HTTPS 和域名

如果你后面继续使用容器内 Nginx 托管前端，也可以：

- 外层再放一个宿主机 Nginx/Caddy 做 TLS 终止
- 或者直接加一个独立网关容器

### 8.2 数据持久化

你已经在 compose 里用了 volume：

- PostgreSQL 数据卷
- Redis 数据卷

这很好，但你还要加一个认知：

**volume 不是备份。**

你仍然需要：

- 定期导出 PostgreSQL
- 备份 `.env`
- 备份上传文件目录

### 8.3 上传文件目录

当前 API 服务挂载了：

- `./xs-blog-server/app/storage:/app/storage`

这意味着服务器磁盘上的这个目录是真实文件存储位置。

你部署和备份时不能只关注数据库，也要关注这个目录。

### 8.4 防火墙和端口策略

推荐至少明确：

- `80/443` 对公网开放
- `5432` 不要对公网开放
- `6379` 不要对公网开放
- `8000` 最好也不要对公网开放，除非临时调试

如果现在只是为了简单测试而直接暴露端口，后续上正式环境时建议收口。

### 8.5 日志和异常排查

建议至少固定这些排查命令：

```bash
docker compose ps
docker compose logs --tail=200 api
docker compose logs --tail=200 web
docker compose logs --tail=200 migrate
docker compose logs --tail=200 db
docker compose logs --tail=200 redis
```

## 9. 一个更优雅的最小部署方案

如果你不想一上来就上 CI/CD，我建议你至少做到下面这版。

### 目录固定

服务器固定部署目录，例如：

```bash
/srv/xs-blog/xs-blog-base
```

### 固定环境变量文件

生产环境 `.env` 永远留在服务器本地，不跟代码仓库走。

### 固定更新脚本

例如每次都执行同一个脚本：

```bash
./scripts/deploy.sh
```

这个脚本内部统一做：

- 拉代码
- 更新子模块
- 校验 compose
- 重建服务
- 输出状态

这样你的部署就已经从“手工命令”升级成“可重复脚本化部署”。

## 10. 更好的方式是什么

如果你问“有没有比服务器直接 git pull 更好的方式”，答案是有。

更好的长期方式是：

- Git push 到主分支
- CI 自动测试
- CI 自动构建镜像
- 推送到镜像仓库
- 服务器只执行 pull + up

这是更标准的发布链路。

但要注意：

**这不一定是你现在最该先做的事。**

对于当前阶段，更合理的优先级是：

1. 先摆脱复制粘贴部署。
2. 再把服务器部署脚本化。
3. 再考虑 CI/CD 和镜像仓库。

## 11. 我对你当前问题的直接结论

### 结论一

你想的“服务器 git pull 后再运行编排文件完成部署”，方向是对的。

### 结论二

但对于你的仓库结构，正确命令应当是：

```bash
git pull
git submodule update --init --recursive
docker compose up -d --build
```

而不是只有 `git pull`。

### 结论三

服务器上还需要额外处理这些事情：

- Docker 环境
- 生产 `.env`
- HTTPS / 域名 / 端口策略
- 数据备份
- 上传文件目录备份
- 更新脚本

### 结论四

如果你现在想先优雅起来，但又不想一下子太重，最适合你的方案是：

- 保留当前源码构建模式
- 用 Git + 子模块管理版本
- 用 `.env` 管理生产配置
- 用统一 `deploy.sh` 完成更新部署

这已经是非常合理的一步。

## 12. 后续建议

你现在下一步最值得做的，不是立刻上复杂 CI，而是先把这两件事落地：

1. 增加服务器部署脚本。
2. 增加生产环境专用 compose 或反向代理方案。

这样你就已经从“复制粘贴上线”升级到“可重复、可维护的标准部署”了。