# Documentação Técnica: Tela de Treino 1.0

## 1. Arquitetura
O aplicativo utiliza uma arquitetura modular baseada em **Camadas de Responsabilidade**:
*   **Models (`/lib/models`)**: Define a estrutura do exercício, gerenciando estados de conclusão e controladores de texto para cada série.
*   **Services (`/lib/services`)**: 
    *   `StorageService`: Abstrai o `SharedPreferences` para persistência de nomes, cargas e configurações de abas.
    *   `DatabaseService`: Gerencia o banco de dados SQL (`sqflite`) para armazenamento de longo prazo do histórico de força.
*   **Screens (`lib/main.dart`)**: Camada de visualização reativa utilizando `StatefulWidgets`.

## 2. Funcionalidades de Engenharia
*   **Salvamento Automático**: Implementado via `onChanged` em todos os campos de texto e gatilhos de estado nos checkboxes.
*   **Multitarefa (PiP)**: Integração com `pip_view` permitindo que o cronômetro flutue sobre o sistema operacional.
*   **Lógica de Progressão**: Algoritmo que compara a carga atual com a carga máxima concluída no histórico SQL para sugerir aumento de peso.
*   **Gráficos**: Renderização de tendências temporais utilizando o pacote `fl_chart`.

## 3. Gestão de Ciclo de Vida
*   **Vibração**: Padrão háptico personalizado ([500ms, 1000ms]) para alertas.
*   **Memória**: Uso rigoroso de `dispose()` em todos os `TextEditingControllers` e `AnimationControllers` para evitar memory leaks.
