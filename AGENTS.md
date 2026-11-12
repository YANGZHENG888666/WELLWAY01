# 项目约定

## 图片查看（重要）

- **一次只调用一个 `view_image`，禁止在一个回合里并行调用多个 `view_image`。**
- 需要看多张图片时，分多次依次查看，看完一张再调用下一次。

原因：本机 API 代理（CC Switch）会在并行的工具结果之间插入
`<image_resize_notice>` 消息，转成上游请求后会被判为
"assistant message with 'tool_calls' must be followed by tool messages"，
导致 HTTP 400，整个会话历史被拒收、该会话无法继续。
