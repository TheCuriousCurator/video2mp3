#!/bin/bash
# run-demo.sh - Complete end-to-end demo of video2mp3 system

echo "=========================================="
echo "Video2MP3 Complete Demo"
echo "=========================================="
echo ""

echo "Step 1: Undeploying existing services..."
./undeploy.sh

echo ""
echo "Step 2: Deploying all services..."
./deploy.sh

echo ""
echo "Step 3: Starting port forwarding..."
./start-services.sh

echo ""
echo "Step 4: Logging in and getting JWT token..."
rm -f token.txt
curl -X POST -u 'dksahuji@gmail.com:Admin123' http://video2mp3.com/login > token.txt
echo ""
echo "Token saved to token.txt"

echo ""
echo "Step 5: Uploading video file..."
curl -X POST -F 'file=@./agentic_ai-using-external-feedback.mp4' -H "Authorization: Bearer $(cat token.txt)" http://video2mp3.com/upload

echo ""
echo ""
echo "=========================================="
echo "Demo Complete!"
echo "=========================================="
echo ""
echo "What happens next:"
echo "  1. Converter workers are processing the video → MP3"
echo "  2. When complete, notification service will send email to: dksahuji@gmail.com"
echo "  3. Email subject: 'MP3 Download'"
echo "  4. Email body: 'mp3 file_id: <ObjectId> is now ready!'"
echo ""
echo "Monitor progress:"
echo "  kubectl logs -l app=converter -f    # Watch conversion"
echo "  kubectl logs -l app=notification -f # Watch email sending"
echo ""
echo "Check your email inbox for the notification!"
echo ""
echo "Step 6: Download the MP3 file (after receiving email):"
echo "  Replace <file_id> with the ObjectId from your email notification:"
echo ""
echo "  curl --output mp3_download.mp3 -X GET \\"
echo "    -H \"Authorization: Bearer \$(cat token.txt)\" \\"
echo "    \"http://video2mp3.com/download?fid=<file_id>\""
echo ""
echo "  Example:"
echo "  curl --output mp3_download.mp3 -X GET \\"
echo "    -H \"Authorization: Bearer \$(cat token.txt)\" \\"
echo "    \"http://video2mp3.com/download?fid=6908d08362046551e1ec6efa\""
echo ""
