import pika, json


def upload(f, fs, channel, access_claim_payload):
    try:
        fid = fs.put(f)
    except Exception as err:
        print(err)
        return "internal server error", 500

    message = {
        "video_fid": str(fid),
        "mp3_fid": None,
        "username": access_claim_payload["username"],
    }

    try:
        channel.basic_publish(
            exchange="",
            routing_key="video",  # queue name
            body=json.dumps(message),
            properties=pika.BasicProperties(
                # message should be persisted till its removed
                delivery_mode=pika.spec.PERSISTENT_DELIVERY_MODE
            ),
        )
    except Exception as err:
        print(err)
        fs.delete(fid)
        return "internal server error", 500
