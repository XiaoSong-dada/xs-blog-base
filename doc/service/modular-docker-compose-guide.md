# xs-blog 模块化 Docker 编排拆分指南

## 1. 你当前的状态

你现在的仓库结构，已经从“前后端两个独立项目”开始往“主仓库聚合多个子模块”的方向演进了，但编排职责还没有真正上移到主模块。

当前可以确认的现状是：

- `xs-blog-server` 已经有自己的 `Dockerfile`，可以独立构建 API 镜像。
- `xs-blog-server/docker-compose.yml` 仍然在负责 `api`、`migrate`、`db`、`redis` 的整体编排。
- `xs-blog-web` 目前还没有 Dockerfile。
- `xs-blog-db` 目前只是数据库相关资料目录，还没有形成可构建镜像的明确边界。
- `xs-blog-base/docker-compose.yml` 还是空的，因此主模块还没有承担统一启动入口的角色。

这就是你现在觉得“不够优雅、不够工程化”的核心原因：

不是代码没拆，而是“模块归属”和“部署编排归属”还没有对齐。

## 2. 你应该拆成什么样

建议目标不是“所有内容都塞进一个 compose”，而是：

- `xs-blog-base` 负责统一编排。
- `xs-blog-server` 负责后端服务镜像定义。
- `xs-blog-web` 负责前端服务镜像定义。
- `xs-blog-db` 负责数据库基础设施镜像定义或基础设施配置归档。

换句话说，主仓库负责“把模块组装起来”，子模块负责“定义自己如何被构建和运行”。

这是更合理的职责边界：

- 模块内维护自己的 Dockerfile。
- 主模块只维护 docker-compose.yml、环境变量组织方式、跨模块依赖关系。
- 任何单个模块都可以单独开发。
- 所有模块又可以在 base 仓库里一键联调。

## 3. 一个更合理的目标目录

建议最终演进到类似结构：

```text
xs-blog-base/
  docker-compose.yml
  .env.example
  README.md
  doc/
  xs-blog-server/
    Dockerfile
    .dockerignore
    compose/
      api.env.example
  xs-blog-web/
    Dockerfile
    .dockerignore
    nginx.conf
    .env.production
  xs-blog-db/
    postgres/
      Dockerfile
      initdb/
        001_init.sql
        002_seed.sql
    redis/
      Dockerfile
      redis.conf
```

如果你不想把 `xs-blog-db` 再细分成 `postgres` 和 `redis` 两层目录，也可以保留现有目录风格，比如：

```text
xs-blog-db/
  db/
    Dockerfile
    init.sql
  redis/
    Dockerfile
    redis.conf
```

重点不在目录名字，而在于以下事实必须明确：

- PostgreSQL 和 Redis 是两个独立运行时。
- 如果你坚持“每个模块都有自己的 Dockerfile”，那么 `xs-blog-db` 这个模块内部至少应该有两个 Dockerfile，而不是一个。
- 因为一个 Dockerfile 只能定义一个镜像，而你的 db 模块实际上包含两个服务。

这一步很重要。否则你会为了追求“形式上的统一”而把数据库和 Redis 强行塞进一个容器，这在工程上反而更差。

## 4. 我建议的职责划分

### 4.1 xs-blog-base

只做三件事：

- 聚合子模块。
- 提供统一 `docker-compose.yml`。
- 提供顶层 `.env` 或 `.env.example`。

它不应该再保存某个具体业务服务的 Dockerfile。

### 4.2 xs-blog-server

只负责后端镜像构建和后端运行所需文件，例如：

- `Dockerfile`
- Python 依赖
- Alembic 迁移
- API 启动命令
- 运行时所需挂载目录

它不应该再负责 PostgreSQL、Redis 的部署编排。

也就是说，`xs-blog-server/docker-compose.yml` 未来应该退化为以下两种之一：

- 删除。
- 保留为 server 模块自测用的局部 compose，而不是整站唯一入口。

### 4.3 xs-blog-web

负责前端镜像构建，通常是两种模式：

- 开发模式：Vite dev server。
- 生产模式：构建静态资源后由 Nginx 提供服务。

如果你要工程化，建议默认使用“多阶段构建 + Nginx 静态托管”。

### 4.4 xs-blog-db

负责数据库基础设施资源，建议拆成两个服务定义：

- PostgreSQL 镜像或基于官方镜像的轻定制。
- Redis 镜像或基于官方镜像的轻定制。

这个模块的职责不是写业务逻辑，而是维护：

- 初始化 SQL
- Redis 配置
- 持久化目录约定
- 数据库镜像扩展能力

## 5. 最推荐的改造原则

### 原则一：compose 只放在主模块作为总入口

顶层 `xs-blog-base/docker-compose.yml` 作为唯一标准入口：

```bash
docker compose up --build
```

这样任何人进入 base 仓库后，不需要理解各子模块内部细节，就可以把完整系统拉起来。

### 原则二：每个业务模块只维护自己的 Dockerfile

这意味着：

- `xs-blog-server/Dockerfile` 继续保留。
- `xs-blog-web/Dockerfile` 需要新增。
- `xs-blog-db` 内部要补齐 PostgreSQL 和 Redis 的 Dockerfile，或者明确只使用官方镜像而不自定义。

### 原则三：环境变量由顶层统一管理

推荐把运行时环境变量上移到 base 仓库，例如：

- `xs-blog-base/.env`
- `xs-blog-base/.env.example`

然后顶层 compose 通过 `env_file` 或变量替换给各服务注入。

不要继续把全站环境变量只放在 `xs-blog-server/compose/.env` 里，因为那会导致：

- web 模块无法共享统一环境入口。
- db 模块的配置归属不清。
- base 模块失去“总控台”价值。

### 原则四：迁移任务属于 server 服务域，但由 base 编排触发

`migrate` 的本质不是基础设施，而是后端应用生命周期的一部分。

所以：

- `migrate` 仍然应该使用 `xs-blog-server` 的镜像。
- 但它应当由 `xs-blog-base/docker-compose.yml` 统一声明。

### 原则五：数据库初始化和 Alembic 迁移不要重复建表

这点你现在的 README 已经提到过，后续要明确固定策略：

- 若你使用 Alembic 管理结构演进，`init.sql` 只做扩展、用户、权限、初始库级对象准备。
- 不要再让 `init.sql` 和 Alembic 同时完整建表。

否则后面会持续出现初始化冲突。

## 6. 推荐的拆分顺序

不要一次性大改。按下面顺序改，风险最低。

### 第一步：让 xs-blog-base 成为真正的总入口

在 `xs-blog-base` 根目录创建正式的 `docker-compose.yml`，把当前 `xs-blog-server/docker-compose.yml` 的职责迁移上来。

这一步先不追求完美，只做一件事：

- 保证以后统一从 base 根目录启动整个系统。

### 第二步：把 db 和 redis 的定义迁移到 xs-blog-db 目录语义下

你现在的数据库和 Redis 配置实际上还在 server 模块附近。

应该改成：

- PostgreSQL 初始化 SQL 放在 `xs-blog-db`。
- Redis 配置放在 `xs-blog-db`。
- 顶层 compose 从 `xs-blog-db` 路径引用这些文件。

这一步完成后，server 模块就不再“拥有”基础设施文件。

### 第三步：为 xs-blog-web 补 Dockerfile

建议新增前端 Dockerfile，采用多阶段构建：

1. Node 镜像执行 `pnpm install` 和 `pnpm build`
2. Nginx 镜像托管 `dist`

这样 web 模块才真正成为可被顶层 compose 管理的独立部署单元。

### 第四步：把顶层环境变量收敛到 base 仓库

把目前散落在 server 模块里的环境变量重新整理成：

- 顶层共享变量
- 仅 server 使用的变量
- 仅 db 使用的变量
- 仅 web 使用的变量

推荐做法是：

- `xs-blog-base/.env.example` 作为模板。
- `xs-blog-base/.env` 作为本地实际值。

### 第五步：精简 server 模块内部 compose

迁移完成后，你有两个选择：

- 直接删除 `xs-blog-server/docker-compose.yml`
- 保留一个仅用于后端自测的 compose，但 README 明确声明“主启动入口在 base 根目录”

如果你的目标是工程统一，我更倾向于删除，避免双入口长期漂移。

## 7. 推荐的顶层 compose 形态

下面是一种更符合你当前目标的顶层编排思路。

```yaml
services:
  db:
    build:
      context: ./xs-blog-db/db
    container_name: icu.xiaosong.blog.db
    env_file:
      - ./.env
    ports:
      - "5432:5432"
    volumes:
      - pg_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB"]
      interval: 5s
      timeout: 5s
      retries: 20

  redis:
    build:
      context: ./xs-blog-db/redis
    container_name: icu.xiaosong.blog.redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  migrate:
    build:
      context: ./xs-blog-server
    container_name: icu.xiaosong.blog.migrate
    env_file:
      - ./.env
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    command: alembic upgrade head

  api:
    build:
      context: ./xs-blog-server
    container_name: icu.xiaosong.blog.api
    env_file:
      - ./.env
    depends_on:
      migrate:
        condition: service_completed_successfully
    ports:
      - "8000:8000"
    volumes:
      - ./xs-blog-server/app/storage:/app/storage
    command: uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

  web:
    build:
      context: ./xs-blog-web
    container_name: icu.xiaosong.blog.web
    depends_on:
      api:
        condition: service_started
    ports:
      - "80:80"

volumes:
  pg_data:
  redis_data:
```

这个结构有几个优点：

- 构建入口统一。
- 子模块边界清晰。
- 基础设施配置归属明确。
- 后续 CI/CD 更容易做矩阵构建和按模块发布。

## 8. 关于 xs-blog-db 是否一定要有 Dockerfile

这里我直接给你工程判断，不绕弯子。

### 情况一：你只是在用官方镜像，不需要镜像定制

那其实不一定要写 Dockerfile。

例如 PostgreSQL 直接用：

- `image: postgres:16`

Redis 直接用：

- `image: redis:8-alpine`

然后把 `init.sql` 和 `redis.conf` 通过 volume 挂进去。

这是最简单、最稳定、最符合基础设施实际的做法。

### 情况二：你希望“模块完整自描述”

那就给 `xs-blog-db` 里的 PostgreSQL 和 Redis 各自补 Dockerfile。

例如：

- PostgreSQL Dockerfile：基于 `postgres:16`，拷贝初始化脚本。
- Redis Dockerfile：基于 `redis:8-alpine`，拷贝配置文件并设置启动命令。

这也没问题，但你要清楚，这样做的收益主要是：

- 目录归属更完整。
- 未来做镜像仓库管理更统一。
- 基础设施配置可以直接版本化进镜像。

代价是：

- 维护两个额外镜像。
- 构建速度稍慢。
- 调试复杂度略高。

### 我的建议

如果你现在目标是先完成架构收口，而不是追求每个服务都必须 build，那么优先推荐：

- `xs-blog-server` 和 `xs-blog-web` 使用 Dockerfile。
- `xs-blog-db` 先使用官方镜像 + 模块目录挂载配置。

等你后面需要更强一致性时，再把 `xs-blog-db` 升级成两个 Dockerfile。

这是更稳的演进路线。

## 9. 你现在这套工程里最容易踩的坑

### 9.1 不要把数据库配置继续放在 server 模块语义里

这是现在最明显的边界污染。

server 只应该依赖 db，不应该拥有 db。

### 9.2 不要让 base 仓库只是“文档仓库”

既然你已经把它升级成主模块，它就必须承担：

- 统一启动入口
- 顶层环境管理
- 联调编排

否则这个仓库只是名字变了，工程职责没变。

### 9.3 不要同时保留两个长期有效的 compose 入口

比如：

- 一个在 `xs-blog-base`
- 一个在 `xs-blog-server`

这会导致后续配置漂移，最后没人知道哪个才是标准环境。

### 9.4 不要把 db 和 redis 强行塞进一个容器

这不符合容器的单进程职责原则。

你要的是“db 模块统一管理基础设施”，不是“db 模块运行一个超级容器”。

### 9.5 不要把敏感配置继续直接提交到仓库

数据库密码、密钥、邮箱授权码等应该放在：

- 本地 `.env`
- CI/CD Secret
- 部署环境 Secret

仓库里建议只保留 `.env.example`。

## 10. 一个适合你的实际落地方案

如果按“工程化收益最大、改造成本适中”的标准，我建议你直接采用下面这版：

### 方案选择

- `xs-blog-base`：统一 compose。
- `xs-blog-server`：保留并优化现有 Dockerfile。
- `xs-blog-web`：新增 Dockerfile。
- `xs-blog-db`：先不强制自定义镜像，先托管 `init.sql` 和 `redis.conf`，由顶层 compose 挂载官方镜像。

### 这样做的原因

- 改造量适中。
- 能立刻完成“主模块统一编排”。
- 能消除当前 server 模块对基础设施的越权管理。
- 不会为了追求形式统一而引入无意义的复杂度。

### 第二阶段再做的事

等第一阶段稳定后，再考虑：

- 给 `xs-blog-db/db` 增加 PostgreSQL Dockerfile。
- 给 `xs-blog-db/redis` 增加 Redis Dockerfile。
- 把镜像发布流程接入 CI。

## 11. 你可以直接照着执行的迁移清单

1. 在 `xs-blog-base` 根目录写正式的 `docker-compose.yml`。
2. 把 `xs-blog-server/docker-compose.yml` 的编排职责迁到根目录。
3. 把数据库初始化脚本和 Redis 配置归并到 `xs-blog-db` 路径下。
4. 为 `xs-blog-web` 新增 Dockerfile 和 Nginx 配置。
5. 把全站环境变量提升到 `xs-blog-base/.env.example`。
6. 调整 `xs-blog-server` 中所有依赖地址，确保通过服务名 `db`、`redis` 访问。
7. 验证 `docker compose up --build` 可以从 base 根目录拉起完整系统。
8. 删除或降级 `xs-blog-server/docker-compose.yml`，避免双入口。
9. 在 base 仓库 README 中把“如何启动整个系统”写成唯一标准文档。

## 12. 结论

你现在的方向是对的，但要真正变成你期待的样子，关键不是简单地把几个仓库放进一个父目录，而是完成下面这件事：

**让模块拥有自己的构建定义，让 base 拥有唯一的系统编排权。**

这才是“前后端分离 + 主模块聚合”真正工程化的落点。

如果你愿意，下一步最适合直接落地的是两件事：

1. 我直接帮你生成一版 `xs-blog-base/docker-compose.yml`。
2. 我顺手把 `xs-blog-web/Dockerfile` 和 `xs-blog-db` 的推荐目录骨架一起补出来。