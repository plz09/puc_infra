from flask import Flask, request, render_template
import boto3
import os
from werkzeug.utils import secure_filename

app = Flask(__name__)
bucket_name = "puc-914156456046-bucket"  

@app.route('/')
def home():
    return render_template('index.html')

@app.route('/upload', methods=['POST'])
def upload_csv():
    if 'file' not in request.files:
        return "Nenhum arquivo enviado", 400
    
    file = request.files['file']
    if file.filename == '':
        return "Nome de arquivo vazio", 400

    filename = secure_filename(file.filename)

    # Upload para S3
    s3 = boto3.client('s3')
    s3.upload_fileobj(file, bucket_name, f"uploads/{filename}")

    return f"Arquivo <strong>{filename}</strong> enviado com sucesso para o S3!"

if __name__ == "__main__":
    app.run(debug=True)
