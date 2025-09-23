from flask import Flask, request, jsonify
import threading
import time
import sounddevice as sd
import soundfile as sf

# # app = Flask(__name__)

class Recorder:
    def __init__(self):
        self.is_recording = False
        self.save_to = None

    def start_recording(self, save_to):
        if not self.is_recording:
            self.save_to = save_to
            self.is_recording = True
            threading.Thread(target=self._record_audio).start()
            return True
        else:
            return False

    def stop_recording(self):
        if self.is_recording:
            self.is_recording = False
            return True
        else:
            return False

    def _record_audio(self):
        import sounddevice as sd
        duration = 5  # Adjust the recording duration as needed
        channels = 2  # Number of channels
        samplerate = 44100  # Sample rate
        print('_record_audio called')
        with sf.SoundFile(self.save_to, mode='w', samplerate=samplerate, channels=channels, subtype='PCM_24') as file:
            def callback(indata, frames, time, status):
                if status:
                    print(status)
                    file.write(indata.copy())

            # Modify this line to specify the ASIO device ID for the Scarlett 4i4
            asio_device_id = 10  # Replace 0 with the actual ASIO device ID for the Scarlett 4i4

            with sd.InputStream(channels=channels, samplerate=samplerate, device=asio_device_id, callback=callback):
                while self.is_recording:
                    time.sleep(0.1)

recorder = Recorder()
if __name__ == '__main__':
    recorder.start_recording(r"C:\Users\abush\Desktop\audio_testing.wav")
    time.sleep(5
)c    recorder.stop_recording()



# save_to = r"C:\Users\abush\Desktop\audio_testing.wav"
# duration = 5  # Adjust the recording duration as needed
# channels = 3  # Number of channels
# samplerate = 44100  # Sample rate
# with sf.SoundFile(save_to, mode='w', samplerate=samplerate, channels=channels, subtype='PCM_24') as file:
#     def callback(indata, frames, time, status):
#         if status:
#             print(status)
#             file.write(indata.copy())

#     # Modify this line to specify the ASIO device ID for the Scarlett 4i4
#     asio_device_id = 10  # Replace 0 with the actual ASIO device ID for the Scarlett 4i4

#     with sd.InputStream(channels=channels, samplerate=samplerate, device=asio_device_id, callback=callback):
#         while self.is_recording:
#             time.sleep(0.1)


# @app.route('/start', methods=['POST'])
# def start_recording():
#     if request.method == 'POST':
#         save_to = request.args.get('save_to')
#         print(request.args)
#         print(f'Request to start recording to: {save_to}')
#         if recorder.start_recording(save_to):
#             return jsonify({'status': 'Recording started', 'save_to': save_to}), 200
#         else:
#             return jsonify({'status': 'Recording already in progress'}), 400

# @app.route('/stop', methods=['POST'])
# def stop_recording():
#     if request.method == 'POST':
#         if recorder.stop_recording():
#             return jsonify({'status': 'Recording stopped'}), 200
#         else:
#             return jsonify({'status': 'No recording in progress'}), 400

# if __name__ == '__main__':
#     app.run(host='0.0.0.0', port=8080)


