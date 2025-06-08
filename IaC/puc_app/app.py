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

# Cria uma instância da aplicação Flask
app = Flask(__name__)
bucket_name = "puc-pellizzi09-bucket"

# Rota principal (home)
@app.route('/')
def home():
    logging.info("Página inicial acessada") # Registra acesso à página inicial
    return render_template('index.html') # # Renderiza o template HTML chamado index.html

# Rota para upload de arquivos, aceita apenas método POST
@app.route('/upload', methods=['POST'])
def upload_csv():
    if 'file' not in request.files:
        logging.warning("Tentativa de upload sem arquivo")
        return "Nenhum arquivo enviado", 400
    # Verifica se algum arquivo foi incluído na requisição
    file = request.files['file']
    if file.filename == '':
        logging.warning("Arquivo enviado sem nome")
        return "Nome de arquivo vazio", 400
    # Sanitiza o nome do arquivo para evitar problemas de segurança
    filename = secure_filename(file.filename)

    try:
        # Inicializa o cliente do S3 (usando credenciais padrão da AWS)
        s3 = boto3.client('s3')
        s3 = boto3.client('s3')

        # Faz o upload do arquivo diretamente para a pasta 'uploads/' no bucket especificado
        s3.upload_fileobj(file, bucket_name, f"uploads/{filename}")
        logging.info(f"Arquivo {filename} enviado para S3 com sucesso")
        return f"Arquivo <strong>{filename}</strong> enviado com sucesso para o S3!"
    except Exception as e:
        # Em caso de erro, registra o erro no log e retorna erro 500
        logging.error(f"Erro ao enviar arquivo para o S3: {e}")
        return "Erro interno no servidor", 500
# Executa o servidor Flask localmente em modo debug se o script for chamado diretamente
if __name__ == "__main__":
    app.run(debug=True)
