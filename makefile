# Nome do executável final
TARGET = simulador_cache

# Compilador
CC = gcc

# Flags de compilação
# -Wall: ativa todos os avisos de erro comuns
# -Wextra: ativa alguns avisos extras
# -g: inclui informações de depuração (útil para o GDB)
CFLAGS = -Wall -Wextra -g

# Lista de arquivos fonte
SRCS = main.c cache.c lru.c file_io.c

# Lista de arquivos objeto (transforma .c em .o)
OBJS = $(SRCS:.c=.o)

# Regra principal (padrão)
all: $(TARGET)

# Linkagem do executável
$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $(TARGET) $(OBJS)

# Regras de compilação dos objetos
# O comando abaixo diz que cada .o depende de seu respectivo .c e dos headers
main.o: main.c cache.h lru.h 
	$(CC) $(CFLAGS) -c main.c

cache.o: cache.c cache.h
	$(CC) $(CFLAGS) -c cache.c

lru.o: lru.c lru.h
	$(CC) $(CFLAGS) -c lru.c

# Limpeza dos arquivos temporários
clean:
	rm -f $(OBJS) $(TARGET)

# Rodar o programa
run: all
	./$(TARGET)