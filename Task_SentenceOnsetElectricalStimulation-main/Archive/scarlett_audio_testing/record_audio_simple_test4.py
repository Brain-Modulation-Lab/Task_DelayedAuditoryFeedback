import sounddevice as sd
import numpy as np

def record_audio(duration_seconds, num_channels):
    sample_rate = 44100  # Adjust as needed
    chunk_size = int(sample_rate * duration_seconds)
    
    try:
        # Open a stream for recording from the first 4 channels (adjust as needed)
        with sd.InputStream(device=10, channels=num_channels, samplerate=sample_rate) as stream:
            print(f"Recording {duration_seconds} seconds from {num_channels} channels...")
            audio_data = stream.read(chunk_size)
            print("Recording complete!")

        # Save the recorded audio to a WAV file (you can customize the filename)
        output_filename = r"C:\Users\abush\Desktop\audio_testing.wav"
        sd.write(output_filename, audio_data, sample_rate)
        print(f"Saved audio to {output_filename}")
    
    except Exception as e:
        print(f"Error during recording: {e}")

if __name__ == "__main__":
    recording_duration = 10  # Set the desired recording duration in seconds
    num_channels_to_record = 4  # Specify the number of channels to record
    record_audio(recording_duration, num_channels_to_record)
