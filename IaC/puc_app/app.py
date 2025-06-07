from flask import Flask, request, render_template
import boto3
import os
from werkzeug.utils import secure_filename
import logging

# Configura o logger para salvar em /tmp/app.log
logging.basicConfig(
    filename='/tmp/app.log',
    level=logging.INFO,
    format='%(asctime)s %(levelname)s: %(message)s'
)

app = Flask(__name__)
bucket_name = "puc-914156456046-bucket"

@app.route('/')
def home():
    logging.info("Página inicial acessada")
    return render_template('index.html')

@app.route('/upload', methods=['POST'])
def upload_csv():
    if 'file' not in request.files:
        logging.warning("Tentativa de upload sem arquivo")
        return "Nenhum arquivo enviado", 400
    
    file = request.files['file']
    if file.filename == '':
        logging.warning("Arquivo enviado sem nome")
        return "Nome de arquivo vazio", 400

    filename = secure_filename(file.filename)

    try:
        # Upload para S3
        s3 = boto3.client('s3')
        s3.upload_fileobj(file, bucket_name, f"uploads/{filename}")
        logging.info(f"Arquivo {filename} enviado para S3 com sucesso")
        return f"Arquivo <strong>{filename}</strong> enviado com sucesso para o S3!"
    except Exception as e:
        logging.error(f"Erro ao enviar arquivo para o S3: {e}")
        return "Erro interno no servidor", 500

if __name__ == "__main__":
    app.run(debug=True)
