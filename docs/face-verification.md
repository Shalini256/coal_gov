# Face Verification Attendance

Self check-in now requires a live camera frame. The backend sends the frame to the AI service before writing attendance.

- On the first successful check-in for a worker, the captured face image is enrolled as that worker's reference image.
- Later check-ins must contain exactly one clear face and match the enrolled reference above the configured threshold.
- Failed matches create a `FACE_VERIFICATION_FAILED` attendance anomaly and do not record attendance.
- GPS geofencing, mock-location checks, clock checks, velocity checks, and liveness checks continue to run.

Install the AI service dependencies before starting it:

```bash
cd ai-service
pip install -r requirements.txt
python app.py
```

Set `FACE_MATCH_THRESHOLD` to tune the cosine similarity threshold. The default is `0.72`. A clean install uses OpenCV below version 5 because the Haar cascade API is not available in OpenCV 5.
