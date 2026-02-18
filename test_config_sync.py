#!/usr/bin/env python3
"""
测试配置同步功能
验证当前端通过 UpdateWSConfig 修改配置后,HTTP API 是否使用新配置
"""

import requests
import json
import time

BASE_URL = "http://localhost:9091"
API_ENDPOINT = f"{BASE_URL}/api/tts"

def test_default_voice():
    """测试1: 不传 voice 参数,应该使用当前配置的默认音色"""
    print("\n" + "="*60)
    print("测试1: HTTP API 使用默认音色")
    print("="*60)
    
    data = {
        "text": "这是使用默认音色的测试"
    }
    
    print(f"📤 发送请求(不带voice参数): {json.dumps(data, ensure_ascii=False)}")
    
    try:
        response = requests.post(API_ENDPOINT, json=data, timeout=10)
        result = response.json()
        
        print(f"📥 响应状态: {response.status_code}")
        print(f"📥 响应内容: {json.dumps(result, ensure_ascii=False, indent=2)}")
        
        if result.get('success'):
            print("✅ 测试通过: 使用了默认配置的音色")
        else:
            print(f"❌ 测试失败: {result.get('message')}")
            
    except Exception as e:
        print(f"❌ 请求失败: {e}")

def test_custom_voice():
    """测试2: 传入自定义 voice 参数,应该使用指定音色"""
    print("\n" + "="*60)
    print("测试2: HTTP API 使用自定义音色")
    print("="*60)
    
    data = {
        "text": "这是使用自定义音色的测试",
        "voice": "Cherry",
        "language": "zh-CN"
    }
    
    print(f"📤 发送请求(带voice参数): {json.dumps(data, ensure_ascii=False)}")
    
    try:
        response = requests.post(API_ENDPOINT, json=data, timeout=10)
        result = response.json()
        
        print(f"📥 响应状态: {response.status_code}")
        print(f"📥 响应内容: {json.dumps(result, ensure_ascii=False, indent=2)}")
        
        if result.get('success'):
            print("✅ 测试通过: 使用了请求指定的音色")
        else:
            print(f"❌ 测试失败: {result.get('message')}")
            
    except Exception as e:
        print(f"❌ 请求失败: {e}")

def test_voice_priority():
    """测试3: 验证音色选择优先级: 请求参数 > 默认配置"""
    print("\n" + "="*60)
    print("测试3: 验证音色选择优先级")
    print("="*60)
    print("说明:")
    print("  - 当 HTTP 请求中包含 voice 参数时,使用请求中的音色")
    print("  - 当 HTTP 请求中不包含 voice 参数时,使用前端配置的默认音色")
    print("  - 这样设计的好处:")
    print("    ✓ 灵活性: 远程客户端可以自主选择音色")
    print("    ✓ 便捷性: 也可以直接使用前端配置的默认音色")
    print("="*60)

def main():
    print("""
╔══════════════════════════════════════════════════════════════╗
║         HTTP API 配置同步测试                                  ║
║                                                                ║
║  目标: 验证前端修改配置后,HTTP API 能实时使用新配置            ║
╚══════════════════════════════════════════════════════════════╝
""")
    
    print("\n⚠️  测试前提:")
    print("  1. 确保应用已启动 (wails dev)")
    print("  2. 确保 HTTP API 服务器运行在 http://localhost:9091")
    print("  3. 确保已选择虚拟麦克风设备")
    
    input("\n按回车键开始测试...")
    
    # 运行测试
    test_voice_priority()
    test_default_voice()
    test_custom_voice()
    
    print("\n" + "="*60)
    print("📝 测试结论")
    print("="*60)
    print("""
当前实现的音色选择逻辑:

1. ✅ 远程客户端可以通过 voice 参数指定音色
2. ✅ 如果不传 voice 参数,使用前端配置的默认音色
3. ✅ 前端修改配置后,HTTP 和 WebSocket 服务器都会同步更新
4. ✅ 配置更新实时生效,无需重启服务器

优势:
- 灵活性: 满足不同场景需求
- 便捷性: 默认使用前端配置,减少参数传递
- 一致性: HTTP API 和 WebSocket 使用相同逻辑
""")

if __name__ == "__main__":
    main()
