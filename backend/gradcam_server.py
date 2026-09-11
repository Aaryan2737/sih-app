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
import timm

app = FastAPI()

@app.get("/")
def health_check():
    return {"status": "active", "message": "OptiXAI Grad-CAM Server is running"}

# Global variables for lazy loading
device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
model = None
cam = None
preprocess = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]) 
])

def get_cam_model():
    global model, cam
    if model is None:
        print("Loading model and weights lazily...")
        model = timm.create_model('mobilenetv4_conv_small.e200_r224', pretrained=False, num_classes=4).to(device)
        try:
            model.load_state_dict(torch.load('best_weights.pth', map_location=device))
            print("Loaded best_weights.pth successfully.")
        except Exception as e:
            print(f"Warning: Could not load best_weights.pth ({e}).")
        model.eval()
        target_layers = [model.conv_head]
        cam = GradCAMPlusPlus(model=model, target_layers=target_layers)
    return model, cam

@app.post("/generate_gradcam")
async def generate_gradcam(file: UploadFile = File(...)):
    try:
        current_model, current_cam = get_cam_model()
        
        image_bytes = await file.read()
        img = Image.open(io.BytesIO(image_bytes)).convert('RGB')
        
        input_tensor = preprocess(img).unsqueeze(0).to(device)
        
        img_resized = img.resize((224, 224))
        rgb_img = np.float32(img_resized) / 255
        
        grayscale_cam = current_cam(input_tensor=input_tensor, targets=None)
        grayscale_cam = grayscale_cam[0, :]
        
        cam_image = show_cam_on_image(rgb_img, grayscale_cam, use_rgb=True)
        
        final_image = Image.fromarray(cam_image)
        img_byte_arr = io.BytesIO()
        final_image.save(img_byte_arr, format='JPEG', quality=95)
        img_byte_arr.seek(0)
        
        return Response(content=img_byte_arr.getvalue(), media_type="image/jpeg")
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))