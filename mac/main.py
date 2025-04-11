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
model = YOLO("yolov8n-pose.pt")  # Using pose detection model
cap = cv2.VideoCapture(0)

# Moving average filters for pan and tilt
pan_history = deque(maxlen=AVG_WINDOW_SIZE)
tilt_history = deque(maxlen=AVG_WINDOW_SIZE)

# Store last sent positions
last_sent_pan = 0
last_sent_tilt = 0

def get_person_center(results, frame_width, frame_height):
    global last_sent_pan, last_sent_tilt
    
    # Calculate dynamic step size based on distance to target
    def calculate_step_size(distance):
        # More consistent step size with slight adjustment for small distances
        base_step = 0.25  # 25% base step size
        if abs(distance) < 3:  # When very close
            return 0.35  # Slightly more aggressive
        return base_step
    
    for result in results:
        if result.keypoints is not None:  # Check if pose keypoints are available
            for kpts in result.keypoints:
                # Convert tensor to numpy array and check confidence
                kpts_np = kpts.xy[0].cpu().numpy()
                conf_np = kpts.conf[0].cpu().numpy() if kpts.conf is not None else None
                
                if conf_np is not None and conf_np.mean() > 0.5:  # Check average confidence
                    # Keypoint indices for eyes
                    left_eye_idx = 1
                    right_eye_idx = 2
                    
                    # Get eye positions
                    left_eye = kpts_np[left_eye_idx]
                    right_eye = kpts_np[right_eye_idx]
                    
                    # Only proceed if both eyes are detected (coordinates > 0)
                    if left_eye[0] > 0 and left_eye[1] > 0 and right_eye[0] > 0 and right_eye[1] > 0:
                        # Calculate center point between eyes
                        cx = (left_eye[0] + right_eye[0]) / 2
                        cy = (left_eye[1] + right_eye[1]) / 2
                        
                        # Normalize coordinates to -1 to 1
                        norm_x = (cx - frame_width / 2) / (frame_width / 2)
                        norm_y = (cy - frame_height / 2) / (frame_height / 2)
                        
                        # Apply sigmoid-like function for smoother response
                        def smooth_response(x):
                            return x * (1.0 - 0.7 * x * x)  # More gentle cubic function
                        
                        # Calculate target angles with smoothed response
                        target_pan = smooth_response(norm_x) * 45
                        target_tilt = smooth_response(norm_y) * 30
                        
                        # Add to history
                        pan_history.append(target_pan)
                        tilt_history.append(target_tilt)
                        
                        # Calculate moving average of target positions
                        avg_target_pan = sum(pan_history) / len(pan_history)
                        avg_target_tilt = sum(tilt_history) / len(tilt_history)
                        
                        # Calculate step size based on distance to target
                        pan_distance = avg_target_pan - last_sent_pan
                        tilt_distance = avg_target_tilt - last_sent_tilt
                        
                        # Use dynamic step size
                        pan_step_size = calculate_step_size(pan_distance)
                        tilt_step_size = calculate_step_size(tilt_distance)
                        
                        # Move a fraction of the distance to the target
                        step_pan = last_sent_pan + (pan_distance * pan_step_size)
                        step_tilt = last_sent_tilt + (tilt_distance * tilt_step_size)
                        
                        # Update last sent positions
                        last_sent_pan = step_pan
                        last_sent_tilt = step_tilt
                        
                        return step_pan, step_tilt
    
    # If no person detected, clear the history to prevent bias
    pan_history.clear()
    tilt_history.clear()
    for _ in range(AVG_WINDOW_SIZE):
        pan_history.append(last_sent_pan)
        tilt_history.append(last_sent_tilt)
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

                    # Draw keypoints on frame for visualization
                    if results[0].keypoints is not None:
                        for kpts in results[0].keypoints:
                            kpts_np = kpts.xy[0].cpu().numpy()
                            conf_np = kpts.conf[0].cpu().numpy() if kpts.conf is not None else None
                            
                            if conf_np is not None and conf_np.mean() > 0.5:
                                for kpt in kpts_np:
                                    if kpt[0] > 0 and kpt[1] > 0:  # Only draw valid keypoints
                                        cv2.circle(frame, (int(kpt[0]), int(kpt[1])), 5, (0, 255, 0), -1)

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