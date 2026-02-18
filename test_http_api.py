#!/usr/bin/env python3
"""
HTTP API 测试脚本
测试 TTS HTTP 接口
"""

import requests
import json
import sys
import time

# 配置
HTTP_URL = "http://localhost:9091/api/tts"

def test_simple_request():
    """测试简单的文本请求"""
    print("=" * 50)
    print("测试 1: 简单文本请求")
    print("=" * 50)
    
    payload = {
        "text": "你好，这是一个测试消息"
    }
    
    print(f"发送请求: {json.dumps(payload, ensure_ascii=False)}")
    
    try:
        response = requests.post(HTTP_URL, json=payload, timeout=30)
        print(f"状态码: {response.status_code}")
        print(f"响应: {json.dumps(response.json(), ensure_ascii=False, indent=2)}")
        return response.status_code == 200
    except Exception as e:
        print(f"错误: {e}")
        return False

def test_with_voice():
    """测试带音色参数的请求"""
    print("\n" + "=" * 50)
    print("测试 2: 带音色参数的请求")
    print("=" * 50)
    
    payload = {
        "text": "这是使用特定音色的测试",
        "voice": "Cherry",
        "language": "Auto"
    }
    
    print(f"发送请求: {json.dumps(payload, ensure_ascii=False)}")
    
    try:
        response = requests.post(HTTP_URL, json=payload, timeout=30)
        print(f"状态码: {response.status_code}")
        print(f"响应: {json.dumps(response.json(), ensure_ascii=False, indent=2)}")
        return response.status_code == 200
    except Exception as e:
        print(f"错误: {e}")
        return False

def test_empty_text():
    """测试空文本（应该返回错误）"""
    print("\n" + "=" * 50)
    print("测试 3: 空文本（预期失败）")
    print("=" * 50)
    
    payload = {
        "text": ""
    }
    
    print(f"发送请求: {json.dumps(payload, ensure_ascii=False)}")
    
    try:
        response = requests.post(HTTP_URL, json=payload, timeout=30)
        print(f"状态码: {response.status_code}")
        print(f"响应: {json.dumps(response.json(), ensure_ascii=False, indent=2)}")
        return response.status_code == 400  # 预期返回 400
    except Exception as e:
        print(f"错误: {e}")
        return False

def test_invalid_json():
    """测试无效的 JSON（应该返回错误）"""
    print("\n" + "=" * 50)
    print("测试 4: 无效 JSON（预期失败）")
    print("=" * 50)
    
    try:
        response = requests.post(
            HTTP_URL, 
            data="invalid json", 
            headers={"Content-Type": "application/json"},
            timeout=30
        )
        print(f"状态码: {response.status_code}")
        print(f"响应: {json.dumps(response.json(), ensure_ascii=False, indent=2)}")
        return response.status_code == 400  # 预期返回 400
    except Exception as e:
        print(f"错误: {e}")
        return False

def test_long_text():
    """测试长文本"""
    print("\n" + "=" * 50)
    print("测试 5: 长文本")
    print("=" * 50)
    
    payload = {
        "text": "这是一段较长的测试文本，用于测试 TTS 系统对长文本的处理能力。" * 3
    }
    
    print(f"发送请求 (文本长度: {len(payload['text'])} 字符)")
    
    try:
        start_time = time.time()
        response = requests.post(HTTP_URL, json=payload, timeout=60)
        elapsed = time.time() - start_time
        
        print(f"状态码: {response.status_code}")
        print(f"耗时: {elapsed:.2f} 秒")
        print(f"响应: {json.dumps(response.json(), ensure_ascii=False, indent=2)}")
        return response.status_code == 200
    except Exception as e:
        print(f"错误: {e}")
        return False

def test_concurrent_requests():
    """测试并发请求"""
    print("\n" + "=" * 50)
    print("测试 6: 并发请求（3个）")
    print("=" * 50)
    
    import threading
    
    results = []
    
    def send_request(index):
        payload = {
            "text": f"并发测试消息 {index}"
        }
        try:
            response = requests.post(HTTP_URL, json=payload, timeout=30)
            results.append(response.status_code == 200)
            print(f"请求 {index}: {response.status_code}")
        except Exception as e:
            print(f"请求 {index} 错误: {e}")
            results.append(False)
    
    threads = []
    for i in range(3):
        t = threading.Thread(target=send_request, args=(i+1,))
        threads.append(t)
        t.start()
    
    for t in threads:
        t.join()
    
    return all(results)

def main():
    """运行所有测试"""
    print("\n🧪 HTTP API 测试套件")
    print(f"目标服务器: {HTTP_URL}")
    print("\n")
    
    tests = [
        ("简单文本请求", test_simple_request),
        ("带音色参数", test_with_voice),
        ("空文本验证", test_empty_text),
        ("无效JSON验证", test_invalid_json),
        ("长文本处理", test_long_text),
        ("并发请求", test_concurrent_requests),
    ]
    
    results = []
    for name, test_func in tests:
        try:
            result = test_func()
            results.append((name, result))
            time.sleep(1)  # 测试间隔
        except Exception as e:
            print(f"\n❌ 测试 '{name}' 出现异常: {e}")
            results.append((name, False))
    
    # 打印总结
    print("\n" + "=" * 50)
    print("测试总结")
    print("=" * 50)
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for name, result in results:
        status = "✅ 通过" if result else "❌ 失败"
        print(f"{status} - {name}")
    
    print(f"\n总计: {passed}/{total} 通过")
    
    return 0 if passed == total else 1

if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n\n⚠️  测试被用户中断")
        sys.exit(1)
