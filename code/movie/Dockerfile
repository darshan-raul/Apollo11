
FROM python:3.11-slim
WORKDIR /code
COPY ./requirements.txt /code
COPY ./app /code/app
RUN pip install --no-cache -r requirements.txt
CMD ["fastapi", "run", "app/main.py", "--port", "8000"]