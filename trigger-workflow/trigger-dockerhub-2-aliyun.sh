#!/bin/bash
# 文件名: trigger.sh
# 用途: 循环触发 GitHub Actions Workflow，把 dockerhub 镜像同步到阿里云
# 使用: ./trigger.sh

# GitHub repo 信息
OWNER="liwj-ai"
REPO="scripts"
WORKFLOW="dockerhub-2-aliyun.yml"

# 这里填你的 GitHub Token
GITHUB_TOKEN="替换成你的TOKEN"

TARGET_REGISTRY="registry.cn-hangzhou.aliyuncs.com/liwenjian123/"

# 镜像列表示例
IMAGES=(
    "langgenius/dify-api:1.8.1"
    "langgenius/dify-web:1.8.1"
)

# 循环触发 workflow
for IMAGE in "${IMAGES[@]}"; do
  echo "Triggering workflow for source image: $IMAGE"

  # 提取镜像名（去掉 registry 前缀，保留仓库和tag）
  NAME_WITH_TAG=$(echo "$IMAGE" | awk -F'/' '{print $NF}')
  TARGET_IMAGE="${NAME_WITH_TAG}"

  curl -s -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${OWNER}/${REPO}/actions/workflows/${WORKFLOW}/dispatches" \
    -d "{
      \"ref\":\"main\",
      \"inputs\":{
        \"source_image\":\"${IMAGE}\",
        \"target_registry\":\"${TARGET_REGISTRY}\",
        \"target_image\":\"${TARGET_IMAGE}\"
      }
    }"

  echo "✅ Dispatched: $IMAGE -> ${TARGET_REGISTRY}${TARGET_IMAGE}"
  sleep 10  # 防止触发过快
done
