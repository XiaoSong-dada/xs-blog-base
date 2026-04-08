# xs-blog-service 后端依赖图谱

## 目的与边界

- 本文只用于快速理解后端结构、模块依赖方向、业务定位路径。
- 只探查目录、路由聚合、模块 import 关系，不深读具体实现逻辑。
- 当现有项目概述仍停留在初期结构时，可先用本文完成业务快速落点，再决定是否继续深入代码。

## 快速结论

后端当前主体仍然是分层结构，但已经从“初期的简单 API + Repository”演化为以下形态：

1. API 层负责路由暴露、权限依赖、请求参数接入。
2. Service 层承接主要业务编排，是业务定位的第二跳。
3. Repository 层同时存在同步访问和异步访问两套实现，但文章 API 主链当前已优先收敛到异步 ORM 仓储 ArticleRepoAsync。
4. Security、Core、DB、Utils 提供横切能力，被多个业务模块复用。
5. 主入口通过 app/main.py 和 app/api/__init__.py 聚合所有业务路由。

## 总体依赖方向

```mermaid
flowchart LR
    main[app/main.py] --> api_init[app/api/__init__.py]
    api_init --> api[app/api/*]
    api --> service[app/services/*]
    api --> schema[app/schemas/*]
    api --> security[app/security/*]
    api --> dbdeps[app/db/deps.py]
    service --> repo[app/repositories/*]
    service --> schema
    service --> core[app/core/*]
    service --> utils[app/utils/*]
    service --> dbtx[app/db/transaction.py|app/db/read_connection.py]
    repo --> model[app/models/*]
    repo --> schema
    repo --> repo_base[app/repositories/base.py|sql_builders/*]
    security --> service
    security --> core
    security --> utils
    core --> core_cfg[app/core/config.py]
```

## 分层图谱

### 1. 入口层

核心文件：

- app/main.py
- app/api/__init__.py

扇入：

- app/main.py 被运行入口直接使用。
- app/api/__init__.py 被 app/main.py 聚合加载。

扇出：

- app/main.py 扇出到 api、core、schemas、utils。
- app/api/__init__.py 扇出到 login、users、article、file、publish、email、friend_link、comment、tag 九个 API 模块。

快速定位价值：

- 不确定某个接口有没有暴露时，先看 app/api/__init__.py。
- 不确定全局异常、CORS、静态资源、Redis 生命周期时，先看 app/main.py。

### 2. API 层

目录：app/api

当前业务文件：

- article.py
- comment.py
- email.py
- file.py
- friend_link.py
- login.py
- publish.py
- tag.py
- users.py

API 层扇入：

- 统一由 app/api/__init__.py 聚合。

API 层扇出：

- 主要扇出到 app/services/*。
- 同时依赖 app/schemas/* 作为请求与响应模型。
- 通过 app/security/permissions.py 接入登录与管理员权限。
- 异步接口会通过 app/db/deps.py 获取 AsyncSession。
- 个别接口还会直接引用 app/core/exceptions.py。
- 登录认证入口除 auth_service.py 外，现已额外依赖 captcha_token_service.py 与 schemas/login.py，形成“先签发验证码凭证，再消费凭证完成登录”的双阶段链路。

API 层快速规律：

- 需要找“接口入口”时，先从对应 API 文件开始。
- 需要判断接口权限时，优先看 require_login、require_admin、require_login_optional。
- 需要判断接口走同步事务还是异步会话时，看是否注入 get_db。

### 3. Service 层

目录：app/services

当前业务文件：

- article_service.py
- article_bookmark_service.py
- article_like_service.py
- auth_service.py
- captcha_token_service.py
- comment_service.py
- email_service.py
- file_service.py
- friend_link_service.py
- tag_service.py
- upload_session_service.py
- user_service.py

Service 层扇入：

- 主要被 app/api/* 调用。
- app/security/auth.py 还会反向依赖 user_service.py 获取当前用户。
- user_service.py 会调用 email_service.py 完成验证码校验。
- login.py 会额外调用 captcha_token_service.py 处理验证码凭证签发与一次性消费。

Service 层扇出：

- 向下扇出到 app/repositories/*。
- 向侧面扇出到 app/core/*、app/utils/*、app/db/*。
- 部分 service 直接引用 app/schemas/* 与 app/models/* 进行结构转换。

Service 层快速规律：

- 这是业务定位的主落点。
- 如果一个功能跨多个 repository、需要权限状态、邮件、缓存、文件、事务配合，通常在 service 层汇总。

### 4. Repository 层

目录：app/repositories

当前主要文件：

- article_repo.py
- article_repo_async.py
- article_bookmark_repo.py
- article_like_repo.py
- comment_repo.py
- file_ropo.py
- friend_link_repo.py
- tag_repo.py
- user_repo.py
- base.py
- sql_builders/*

Repository 层扇入：

- 主要被 service 层调用。
- sql_builders/* 被 article_repo.py、user_repo.py 等查询构造模块调用。

Repository 层扇出：

- 向下扇出到 app/models/*。
- 还会扇出到 app/schemas/*、app/repositories/base.py、sql_builders/*。
- 同步 repository 侧重 psycopg + 原生 SQL 封装。
- 异步 repository 侧重 SQLAlchemy AsyncSession。

Repository 层快速规律：

- 需要确认“数据从哪查、怎么分页、哪张模型表参与”时，优先看 repository。
- 文章域虽然仍保留同步 SQL 仓储，但 API 与 service 主链已优先走 article_repo_async.py；同步 repo 更多用于历史兼容与少量遗留路径。

### 5. 横切层

Security：

- auth.py 负责当前用户解析。
- permissions.py 负责路由依赖封装。
- jwt.py 负责令牌生成与解析。
- password.py 负责密码哈希与校验。

Core：

- config.py 提供配置。
- exceptions.py 提供 AppError。
- redis.py 提供 Redis 访问入口。

DB：

- deps.py 提供 AsyncSession 注入。
- transaction.py、read_connection.py 提供同步连接上下文。
- session.py 维护异步会话工厂。

Utils：

- datetime_utils.py 提供时间工具。
- email_utils.py 提供发信能力。
- file_utils.py 提供文件处理。
- pinyin_utils.py 提供文件名转 slug 等能力。
- redis_keys.py 提供 Redis key 规则。
- verification.py 提供基础字符串校验。

横切层扇入：

- 被多个 API、Service、Security、Repository 复用。

横切层扇出：

- 主要扇出到配置、第三方库或更底层基础设施，不直接承接业务入口。

## 业务快速定位

### 建议定位顺序

1. 先找 API 入口，确认业务接口面。
2. 再找同名或近同名 Service，确认业务编排层。
3. 再找 Repository，确认数据访问路径。
4. 最后补看 Schema、Model、Security、Core、Utils。

### 业务链条速查表

| 业务 | 第一入口 | 第二跳 | 第三跳 | 补充定位 |
| --- | --- | --- | --- | --- |
| 认证登录 | app/api/login.py | app/services/captcha_token_service.py、app/services/auth_service.py | app/repositories/user_repo.py | app/schemas/login.py、app/core/redis.py、app/security/jwt.py、app/security/password.py |
| 用户注册与资料 | app/api/users.py | app/services/user_service.py | app/repositories/user_repo.py | app/services/email_service.py、app/security/password.py |
| 文章管理 | app/api/article.py | app/services/article_service.py | app/repositories/article_repo_async.py | app/schemas/article.py、app/models/article.py；列表、详情、创建、修改、删除、发布现已优先走 AsyncSession + ORM |
| 公开发布文章 | app/api/publish.py | app/services/article_service.py | app/repositories/article_repo_async.py | 这是文章域的公开读取入口；列表、详情、搜索、浏览量已统一走异步仓储 |
| 文章点赞 | app/api/article.py | app/services/article_like_service.py | app/repositories/article_like_repo.py | 同时会回查 article_repo_async.py |
| 文章收藏 | app/api/article.py | app/services/article_bookmark_service.py | app/repositories/article_bookmark_repo.py | 同时会回查 article_repo_async.py |
| 评论 | app/api/comment.py | app/services/comment_service.py | app/repositories/comment_repo.py | 同时会回查 article_repo_async.py |
| 标签 | app/api/tag.py | app/services/tag_service.py | app/repositories/tag_repo.py | app/models/tag.py、app/schemas/tag.py |
| 文件上传与导出 | app/api/file.py | app/services/file_service.py | app/repositories/file_ropo.py、app/repositories/article_repo_async.py | app/services/upload_session_service.py、app/utils/file_utils.py |
| 邮件验证码 | app/api/email.py | app/services/email_service.py | app/core/redis.py、app/repositories/user_repo.py | app/utils/email_utils.py |
| 友情链接 | app/api/friend_link.py | app/services/friend_link_service.py | app/repositories/friend_link_repo.py | app/models/friend_link.py、app/schemas/friend_link.py |

### 从初期结构到当前真实位置的映射

如果只记得“文章、用户、登录、友链、文件”这些初期结构描述，可以按下面方式快速跳转：

- 文章相关：先看 article.py 和 publish.py，再看 article_service.py。
- 用户与认证：先看 login.py、users.py，再看 auth_service.py、user_service.py、security/*。
- 评论与标签：先看 comment.py、tag.py，再看对应 service 与 repo。
- 文件与导出：先看 file.py，再看 file_service.py 与 upload_session_service.py。
- 友情链接：先看 friend_link.py，再看 friend_link_service.py。

## 模块扇入 / 扇出摘要

以下扇入 / 扇出以“结构依赖”统计，不按函数调用深度展开。

### 入口与聚合模块

| 模块 | 扇入 | 扇出 |
| --- | --- | --- |
| app/main.py | 运行入口 | app.api、app.core、app.schemas、app.utils |
| app/api/__init__.py | app/main.py | 9 个 API 路由模块 |

### 核心业务模块

| 模块 | 扇入 | 扇出 |
| --- | --- | --- |
| app/services/article_service.py | app/api/article.py、app/api/publish.py | article_repo_async.py、schemas/article.py、core/exceptions.py、utils/datetime_utils.py |
| app/services/captcha_token_service.py | app/api/login.py | app/core/redis.py |
| app/services/article_like_service.py | app/api/article.py | article_like_repo.py、article_repo_async.py |
| app/services/article_bookmark_service.py | app/api/article.py | article_bookmark_repo.py、article_repo_async.py、core/exceptions.py |
| app/services/comment_service.py | app/api/comment.py | comment_repo.py、article_repo_async.py、core/exceptions.py |
| app/services/tag_service.py | app/api/tag.py | tag_repo.py、models/tag.py、schemas/tag.py、core/exceptions.py |
| app/services/user_service.py | app/api/users.py、app/security/auth.py | user_repo.py、email_service.py、schemas/user.py、security/password.py、db/transaction.py、core/exceptions.py、utils/verification.py |
| app/services/auth_service.py | app/api/login.py | user_repo.py、security/password.py、security/jwt.py、db/read_connection.py、schemas/user.py |
| app/services/email_service.py | app/api/email.py、app/services/user_service.py | core/redis.py、user_repo.py、db/read_connection.py、utils/email_utils.py、core/exceptions.py |
| app/services/file_service.py | app/api/file.py | file_ropo.py、article_repo_async.py、upload_session_service.py、schemas/file.py、schemas/article.py、db/transaction.py、core/config.py、core/exceptions.py、utils/file_utils.py、utils/pinyin_utils.py、utils/datetime_utils.py |
| app/services/friend_link_service.py | app/api/friend_link.py | friend_link_repo.py、schemas/friend_link.py、models/friend_link.py、core/exceptions.py |
| app/services/upload_session_service.py | app/api/file.py、app/services/file_service.py | core/redis.py、utils/redis_keys.py |

### 横切模块

| 模块 | 扇入 | 扇出 |
| --- | --- | --- |
| app/security/permissions.py | 多个 API 路由 | app/security/auth.py |
| app/security/auth.py | app/security/permissions.py | app/security/jwt.py、app/services/user_service.py |
| app/core/exceptions.py | 多个 API、Service | 无明显业务扇出 |
| app/db/deps.py | article.py、comment.py、file.py、friend_link.py、publish.py、tag.py | session.py |
| app/repositories/base.py | user_repo.py、article_repo.py、file_ropo.py | psycopg 基础执行能力 |

## 结构观察

当前结构上值得先知道的点：

1. 文章域仍保留同步和异步两套 repository，但 API 主链已统一收敛到 article_repo_async.py；需要排查线上接口行为时优先看异步仓储。
2. 用户认证并不只在 auth_service.py，权限链还会经过 security/auth.py 和 security/permissions.py。
3. 文件导出链并不只在 file_service.py，还依赖 upload_session_service.py、Redis 会话状态，以及 ArticleRepoAsync 的文章导出查询能力。
4. 邮件验证码链会被用户注册流程复用，因此 email_service.py 不只是独立邮件接口。
5. friend_link.py 当前直接 import 了 friend_link_repo.py，但结构上真正业务主链仍应以 friend_link_service.py 为准。
6. 文件 repository 文件名当前是 file_ropo.py，定位文件上传链路时需要注意这个命名。

## 推荐阅读顺序

若要在最短时间内建立后端认知，建议按下列顺序看结构：

1. app/main.py
2. app/api/__init__.py
3. 对应业务 API 文件
4. 对应业务 Service 文件
5. 对应业务 Repository 文件
6. 必要时再补 Schema、Model、Security、Core、Utils