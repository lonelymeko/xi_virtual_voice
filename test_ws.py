#!/usr/bin/env python3
"""测试 WebSocket 连接（支持心跳和长时间 TTS 处理）"""
import json
from websocket import create_connection, WebSocketTimeoutException, ABNF
import time
import threading

ws_url = "ws://localhost:7878/ws"

def receive_loop(ws, stop_event):
    """持续接收消息的线程"""
    while not stop_event.is_set():
        try:
            # 设置接收超时为 1 秒，这样可以定期检查 stop_event
            ws.settimeout(1.0)
            opcode, data = ws.recv_data()
            
            if opcode == ABNF.OPCODE_TEXT:
                message = data.decode('utf-8')
                try:
                    msg_data = json.loads(message)
                    msg_type = msg_data.get("type", "unknown")
                    
                    if msg_type == "response":
                        if msg_data.get("success"):
                            print(f"✅ TTS 响应: {msg_data.get('message')}")
                        else:
                            print(f"❌ TTS 错误: {msg_data.get('message')}")
                    elif msg_type == "pong":
                        print(f"💗 收到服务器 pong")
                    else:
                        print(f"📥 收到消息: {message}")
                except json.JSONDecodeError:
                    print(f"📥 收到文本: {message}")
                    
            elif opcode == ABNF.OPCODE_PING:
                print(f"💓 收到服务器 ping，自动回复 pong")
                # websocket-client 库会自动回复 pong
                
        except WebSocketTimeoutException:
            # 超时是正常的，继续循环
            continue
        except Exception as e:
            if not stop_event.is_set():
                print(f"⚠️ 接收消息出错: {e}")
            break

def test_websocket():
    print(f"🔍 测试连接到: {ws_url}")
    try:
        # 创建连接，初始超时为 10 秒（用于连接）
        ws = create_connection(ws_url, timeout=10)
        print("✅ WebSocket 连接成功!")
        
        # 连接成功后，禁用超时（持续连接）
        ws.settimeout(None)
        
        # 启动接收消息线程
        stop_event = threading.Event()
        receive_thread = threading.Thread(target=receive_loop, args=(ws, stop_event), daemon=True)
        receive_thread.start()
        print("💓 消息接收线程已启动")
        
        # 发送测试消息 1
        test_message = "你好，这是第一条测试消息"
        print(f"\n📤 发送纯文本: {test_message}")
        ws.send(test_message)
        print("⏳ 等待 TTS 处理... (可能需要几秒钟)")
        time.sleep(8)  # 等待 TTS 完成
        
        # 发送 JSON 格式消息
        json_message = json.dumps({
            "type": "text",
            "text": "这是 JSON 格式的测试消息",
            "voice": "Cherry",
            "language": "Auto"
        })
        print(f"\n📤 发送 JSON: {json_message}")
        ws.send(json_message)
        print("⏳ 等待 TTS 处理...")
        time.sleep(8)  # 等待 TTS 完成
        
        # 测试心跳
        print(f"\n💓 测试心跳...")
        ping_msg = json.dumps({"type": "ping"})
        ws.send(ping_msg)
        print("📤 发送 ping")
        time.sleep(1)  # 等待 pong 响应
        
        # 保持连接 60 秒，观察心跳和长时间连接
        print(f"\n⏳ 保持连接 60 秒，观察服务器心跳...")
        print("   （服务器每 50 秒发送一次 ping）")
        time.sleep(60)
        
        # 停止接收线程
        stop_event.set()
        receive_thread.join(timeout=2)
        
        ws.close()
        print("\n✅ 测试完成!")
        
    except ConnectionRefusedError:
        print("❌ 连接被拒绝 - WebSocket 服务器未启动")
        print("请先启动你的 Wails 应用")
    except TimeoutError:
        print("❌ 连接超时 - 服务器未响应")
    except Exception as e:
        print(f"❌ 错误: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_websocket()
