from flask import Flask, request, jsonify
import threading
import time
import soundfile as sf
import importlib
# import sounddevice


app = Flask(__name__)

class Recorder:
    def __init__(self):
        self.is_recording = False
        self.save_to = None

    def start_recording(self, save_to):
        print('start_recording fcn')

        if not self.is_recording:
            self.save_to = save_to
            self.is_recording = True
            print('changed self.is_recording to true')

            threading.Thread(target=self._record_audio).start()
            return True
        else:
            return False

    def stop_recording(self):
        print('stop_recording fcn')
        if self.is_recording:
            self.is_recording = False
            print('changed self.is_recording to false')
            return True
        else:
            return False

    def _record_audio(self):
        import soundfile as sf
        import numpy as np

        import sounddevice
        import pyaudio
        importlib.reload(pyaudio) 
        importlib.reload(sounddevice) 

        sounddevice._terminate()
        print("sd initialized: " + str(sounddevice._initialized))
        sounddevice._initialize()
        print("sd initialized: " + str(sounddevice._initialized))


        print('_record_audio fcn')

        nchans = 3
        device = sounddevice.query_devices('Focusrite USB ASIO, ASIO')
        print(f"Recording from device: {device}")
        device_id = device['index']
        samplerate = 44100
        block_duration =50


        with sf.SoundFile(self.save_to, mode='w', samplerate=samplerate, channels=nchans, subtype='PCM_24') as file:
            def callback(indata, frames, time, status):
                if status:
                    text = ' ' + str(status) + ' '
                    print('\x1b[34;40m', text.center(args.columns, '#'),
                          '\x1b[0m', sep='')
                if np.any(indata):
                    file.write(indata.copy())
                else:
                    print('no input')

            with sounddevice.InputStream(device=device_id, channels=nchans, callback=callback,
                                blocksize=int(samplerate * block_duration / 1000),
                                samplerate=samplerate):
                while self.is_recording:
                    time.sleep(0.1) 
                print('exiting the recording while loop')
                sounddevice._terminate()
                return

recorder = Recorder()
print('recorder initialized')

@app.route('/start', methods=['POST'])
def start_recording():
    if request.method == 'POST':
        print(request)

        save_to = request.args.get('save_to')
        save_to = save_to.encode('unicode_escape')
        print(f'Request to start recording to: {save_to}')
        if recorder.start_recording(save_to):
            return jsonify({'status': 'Recording started'}), 200
        else:
            return jsonify({'status': 'Recording already in progress'}), 400

@app.route('/stop', methods=['POST'])
def stop_recording():
    if request.method == 'POST':
        if recorder.stop_recording():
            return jsonify({'status': 'Recording stopped'}), 200
        else:
            return jsonify({'status': 'No recording in progress'}), 400

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)


