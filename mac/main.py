import asyncio
import cv2
from ultralytics import YOLO
from bleak import BleakClient, BleakScanner
import time
from collections import deque

# BLE Constants
SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
POSITION_CHAR_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8"
DEVICE_NAME = "CameraRobot"
RECONNECT_DELAY = 5  # seconds to wait before attempting reconnect
TARGET_FPS = 5  # Target frames per second for processing
FRAME_INTERVAL = 1.0 / TARGET_FPS  # Time between frames in seconds
AVG_WINDOW_SIZE = 5  # Number of frames to average over

# Camera and detection model
model = YOLO("yolov8n.pt")  # or yolov10n.pt if installed
cap = cv2.VideoCapture(0)

# Moving average filters for pan and tilt
pan_history = deque(maxlen=AVG_WINDOW_SIZE)
tilt_history = deque(maxlen=AVG_WINDOW_SIZE)

def get_person_center(results, frame_width, frame_height):
    for box in results[0].boxes:
        if int(box.cls[0]) == 0:  # class 0 is 'person' in COCO
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            cx = (x1 + x2) / 2
            cy = (y1 + y2) / 2
            
            # Normalize coordinates to -1 to 1
            norm_x = (cx - frame_width / 2) / (frame_width / 2)
            norm_y = (cy - frame_height / 2) / (frame_height / 2)
            
            # Apply sigmoid-like function for smoother response
            # This creates a curve that's steeper at the edges and flatter in the center
            def smooth_response(x):
                return x * (1.0 - 0.7 * x * x)  # More gentle cubic function
            
            # Calculate angles with smoothed response
            pan = smooth_response(norm_x) * 45  # Removed negative sign
            tilt = -smooth_response(norm_y) * 30  # Keep tilt negative for correct up/down
            
            # Add to history
            pan_history.append(pan)
            tilt_history.append(tilt)
            
            # Calculate moving average
            avg_pan = sum(pan_history) / len(pan_history)
            avg_tilt = sum(tilt_history) / len(tilt_history)
            
            return avg_pan, avg_tilt
    return None, None

async def connect_to_robot():
    while True:
        try:
            device = await BleakScanner.find_device_by_filter(lambda d, ad: d.name == DEVICE_NAME)
            if not device:
                print("Robot not found over BLE, retrying...")
                await asyncio.sleep(RECONNECT_DELAY)
                continue

            client = BleakClient(device)
            await client.connect()
            print("Connected to robot!")
            return client
        except Exception as e:
            print(f"Connection failed: {e}")
            print(f"Retrying in {RECONNECT_DELAY} seconds...")
            await asyncio.sleep(RECONNECT_DELAY)

async def run_tracking():
    client = None
    last_frame_time = time.time()
    
    # Initialize history with zeros
    for _ in range(AVG_WINDOW_SIZE):
        pan_history.append(0)
        tilt_history.append(0)
    
    while True:
        try:
            if client is None or not client.is_connected:
                client = await connect_to_robot()

            while cap.isOpened():
                current_time = time.time()
                elapsed = current_time - last_frame_time
                
                if elapsed >= FRAME_INTERVAL:
                    ret, frame = cap.read()
                    if not ret:
                        break

                    results = model.predict(source=frame, verbose=False)
                    height, width, _ = frame.shape
                    pan, tilt = get_person_center(results, width, height)

                    if pan is not None and tilt is not None:
                        pan = max(min(pan, 90), -90)   # clamp values if needed
                        tilt = max(min(tilt, 90), -90)
                        message = f"{pan:.2f},{tilt:.2f}"
                        print(f"Sending: {message}")
                        try:
                            await client.write_gatt_char(POSITION_CHAR_UUID, message.encode())
                        except Exception as e:
                            print(f"Error sending data: {e}")
                            break  # Break inner loop to attempt reconnection

                    cv2.imshow("YOLO View", frame)
                    last_frame_time = current_time

                key = cv2.waitKey(1) & 0xFF
                if key == ord('q') or key == 27:  # 'q' or ESC key
                    return

        except Exception as e:
            print(f"Error in main loop: {e}")
            if client:
                try:
                    await client.disconnect()
                except:
                    pass
            client = None
            print(f"Retrying in {RECONNECT_DELAY} seconds...")
            await asyncio.sleep(RECONNECT_DELAY)

    cap.release()
    cv2.destroyAllWindows()

asyncio.run(run_tracking())