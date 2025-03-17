import os
import requests
import zipfile
import io
import json
import shutil
from datetime import datetime, timedelta

# 从环境变量读取 GitHub 相关信息
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")
OWNER = os.getenv("OWNER")
REPO = os.getenv("REPO")
WX_WEBHOOK_KEY = os.getenv("WX_WEBHOOK_KEY")
# 关键字列表（从环境变量获取，多个关键字用 "," 分隔）
SENSITIVE_KEYWORDS = os.getenv("SENSITIVE_KEYWORDS", "").split(",")

# 计算昨天的时间范围（UTC 时间）
yesterday = datetime.utcnow() - timedelta(days=1)
START_TIME = yesterday.strftime("%Y-%m-%dT00:00:00Z")
# END_TIME = yesterday.strftime("%Y-%m-%dT23:59:59Z")
END_TIME = datetime.now().strftime("%Y-%m-%dT%H:%M:%SZ")
# START_TIME = "2025-02-06T00:00:00Z"
# END_TIME = "2025-02-06T23:59:59Z"


HEADERS = {
    "Authorization": f"Bearer {GITHUB_TOKEN}",
    "Accept": "application/vnd.github.v3+json",
}

def get_failed_runs():
    url = f"https://api.github.com/repos/{OWNER}/{REPO}/actions/runs?status=failure&per_page=100"
    failed_runs = []

    while url:
        response = requests.get(url, headers=HEADERS)
        response.raise_for_status()
        data = response.json()

        for run in data.get("workflow_runs", []):
            created_at = run["created_at"]
            if START_TIME <= created_at <= END_TIME:
                failed_runs.append(run["id"])

        # 获取分页链接（GitHub API 的 Link 头部会提供下一页链接）
        url = response.links.get("next", {}).get("url")

    print(f"获取到 {len(failed_runs)} 个失败的 workflow runs")
    return failed_runs

def download_logs(run_id):
    """ 下载指定 run_id 的日志，并保存到本地 logs.zip """
    url = f"https://api.github.com/repos/{OWNER}/{REPO}/actions/runs/{run_id}/logs"

    response = requests.get(url, headers=HEADERS, stream=True)
    if response.status_code == 404:
        print(f"❌ 日志 {run_id} 不存在，可能被删除")
        return None
    response.raise_for_status()

    # 将 ZIP 文件分块写入，确保完整下载
    zip_path = f"logs_{run_id}.zip"
    with open(zip_path, "wb") as f:
        shutil.copyfileobj(response.raw, f)  # 按块写入，避免 content 长度不完整

    print(f"✅ 日志已完整下载到 {zip_path}")

    # 解压到 logs_{run_id}/ 目录
    extract_path = f"logs_{run_id}/"
    os.makedirs(extract_path, exist_ok=True)

    with zipfile.ZipFile(zip_path, "r") as zip_ref:
        zip_ref.extractall(extract_path)

    print(f"✅ 日志已解压到 {extract_path}")

    return extract_path  # 返回解压后的目录路径

def search_sensitive_info(logs_dir):
    """ 在解压后的日志文件中查找敏感关键字 """
    matches = []

    for root, _, files in os.walk(logs_dir):
        for file in files:
            log_path = os.path.join(root, file)
            with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    for keyword in SENSITIVE_KEYWORDS:
                        if keyword in line:
                            return True

    return False

def check_empty_dirs(logs_dir):
    may_matches = []
    """ 检查 logs_dir 下的子文件夹是否为空，若为空则记录 """
    for sub_dir in os.listdir(logs_dir):
        sub_dir_path = os.path.join(logs_dir, sub_dir)
        if os.path.isdir(sub_dir_path):
            # 检查子文件夹是否为空
            if not any(os.scandir(sub_dir_path)):  # 子文件夹为空
                return True

    return False

def send_markdown_webhook(msg, url):
    webhook_url = f"https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key={WX_WEBHOOK_KEY}"

    # 格式化Markdown消息
    content = f"**{msg}:** {url}"

    payload = {
        "msgtype": "markdown",
        "markdown": {
            "content": content
        }
    }

    response = requests.post(webhook_url, json=payload)
    return response.status_code, response.text

if __name__ == "__main__":
    print(f"🔍 获取 {START_TIME} ~ {END_TIME} 失败的 workflow logs...")
    failed_runs = get_failed_runs()
    print(f"✅ 找到 {len(failed_runs)} 个失败运行")
    matches = ""
    may_matches = ""
    for run_id in failed_runs:
        web_url = f"https://github.com/{OWNER}/{REPO}/actions/runs/{run_id}"
        print(f"⬇️ 下载日志 {run_id}...")
        logs_dir = download_logs(run_id)
        if not logs_dir:
            continue
        print(f"🔎 搜索敏感关键字...")
        if search_sensitive_info(logs_dir):
            print(f"🚨 发现敏感信息泄露！run_id: {run_id}")
            matches += f"\n\n[{run_id}]({web_url}) "
        elif check_empty_dirs(logs_dir):
            print(f"🚨 发现敏感信息可能泄露！run_id: {run_id}")
            may_matches += f"\n\n[{run_id}]({web_url}) "
        else:
            print(f"✅ run_id {run_id} 日志无敏感信息")
    if matches:
        msg = "敏感信息泄露"
        send_markdown_webhook(msg, matches)
    if may_matches:
        msg = "敏感信息可能泄露"
        send_markdown_webhook(msg, may_matches)
