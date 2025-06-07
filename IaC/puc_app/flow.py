# -*- coding: utf-8 -*-
from prefect import task
import boto3
import pandas as pd
from io import BytesIO

BUCKET = "puc-pellizzi09-bucket"
ORIGEM = "uploads/"
DESTINO = "processed/"

# Essa task lista os arquivos csv no S3
@task
def listar_arquivos_csv():
    s3 = boto3.client("s3")
    response = s3.list_objects_v2(Bucket=BUCKET, Prefix=ORIGEM)

    arquivos = []
    for obj in response.get("Contents", []):
        key = obj["Key"]
        if key.endswith(".csv"):
            arquivos.append(key)

    if not arquivos:
        print("Nenhum arquivo CSV encontrado.")
    return arquivos

# Essas task extrai arquivos csv e retorna um dataframe
@task
def extrair_csv(s3_key):
    s3 = boto3.client("s3")
    response = s3.get_object(Bucket=BUCKET, Key=s3_key)
    conteudo = response["Body"].read()

    df = pd.read_csv(BytesIO(conteudo))
    nome_arquivo = s3_key.split("/")[-1]
    print(f"Extraído: {s3_key} ({len(df)} linhas)")
    return df, nome_arquivo


# Essa task transforma a cloluna valor e acrescenta o R$ e formata para o padrao brasileiro
@task
def transformar(df):
    df["valor"] = df["valor"].apply(lambda x: f"R$ {x:,.2f}".replace(",", "X").replace(".", ",").replace("X", "."))
    print("Coluna 'valor' formatada com prefixo 'R$'")
    return df

# Essa task carrega de volta para o S3. primeiro salva em memoria com bytesIO e depois carrega na pasta processed
@task
def carregar(df, nome_arquivo):
    s3 = boto3.client("s3")
    buffer = BytesIO()
    df.to_csv(buffer, index=False)
    buffer.seek(0)

    destino_key = f"{DESTINO}{nome_arquivo}"
    s3.upload_fileobj(buffer, BUCKET, destino_key)
    print(f"Arquivo salvo em: s3://{BUCKET}/{destino_key}")

if __name__ == "__main__":
    arquivos = listar_arquivos_csv.run()
    for arq in arquivos:
        df, nome = extrair_csv.run(arq)
        df_tratado = transformar.run(df)
        carregar.run(df_tratado, nome)
