import io
import torch
import torch.nn as nn
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import Response
import traceback
from PIL import Image
import numpy as np
from torchvision import transforms
from pytorch_grad_cam import GradCAMPlusPlus
from pytorch_grad_cam.utils.image import show_cam_on_image

app = FastAPI()

# ==========================================
# 1. Model Initialization
# ==========================================
import timm

# Initialize device and model
device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
model = timm.create_model('mobilenetv4_conv_small.e200_r224', pretrained=False, num_classes=4).to(device)

try:
    # Load your best_weights.pth state dictionary
    model.load_state_dict(torch.load('best_weights.pth', map_location=device))
    print("Loaded best_weights.pth successfully.")
except Exception as e:
    print(f"Warning: Could not load best_weights.pth ({e}). Please ensure the file exists in the backend directory.")

model.eval()

# ==========================================
# 2. Target Layer Identification
# ==========================================
# Target the final convolutional layer of MobileNetV4.
# Depending on your specific model definition (e.g., from `timm`), this path might be `model.features[-1]` or `model.conv_head`.
target_layers = [model.conv_head]

# Initialize Grad-CAM++
cam = GradCAMPlusPlus(model=model, target_layers=target_layers)

# Define PyTorch ImageNet preprocessing
preprocess = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]) 
])

# ==========================================
# 3 & 4 & 5. API Endpoint, GradCAM++ Extraction, and Blending
# ==========================================
@app.post("/generate_gradcam")
async def generate_gradcam(file: UploadFile = File(...)):
    try:
        # Read the raw uploaded fundus image
        image_bytes = await file.read()
        img = Image.open(io.BytesIO(image_bytes)).convert('RGB')
        
        # Preprocess image into tensor
        input_tensor = preprocess(img).unsqueeze(0).to(device)
        
        # Calculate original RGB image mapped to [0, 1] for blending
        img_resized = img.resize((224, 224))
        rgb_img = np.float32(img_resized) / 255
        
        # Run GradCAMPlusPlus
        # Note: targets=None automatically targets the highest scoring logit
        grayscale_cam = cam(input_tensor=input_tensor, targets=None)
        grayscale_cam = grayscale_cam[0, :]
        
        # Blend using show_cam_on_image to overlay the heatmap
        cam_image = show_cam_on_image(rgb_img, grayscale_cam, use_rgb=True)
        
        # Convert back to PIL Image and bytes
        final_image = Image.fromarray(cam_image)
        img_byte_arr = io.BytesIO()
        final_image.save(img_byte_arr, format='JPEG', quality=95)
        img_byte_arr.seek(0)
        
        # Return the blended image file directly in the HTTP response
        return Response(content=img_byte_arr.getvalue(), media_type="image/jpeg")
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    # Run locally on port 8000
    uvicorn.run(app, host="0.0.0.0", port=8000)
