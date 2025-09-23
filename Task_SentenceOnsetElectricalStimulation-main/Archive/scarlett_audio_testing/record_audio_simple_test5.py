import sounddevice as sd
import numpy as np


sd.default.device = 'Focusrite USB ASIO'

duration = 5  # seconds
fs=44100
myrecording = sd.rec(duration * fs, samplerate=fs, channels=2)
sd.wait()

sd.play(myrecording, fs)
sd.wait()


