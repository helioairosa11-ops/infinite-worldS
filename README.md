# Infinite Worlds

Um jogo sandbox voxel 3D de sobrevivência, construção, exploração e multijogador desenvolvido em **Godot 4.4 (GDScript + Shaders GLSL)**.

## Funcionalidades Principais

- **Mundo Procedural Infinito por Seeds:**
  - 12 Biomas distintos (Planícies Verdes, Floresta de Carvalhos, Bosque de Bétulas, Taiga Boreal, Tundra Gelada, Deserto Dourado, Meseta Vermelha/Badlands, Pântano Brilhante, Cordilheira Alpina, Oceano Profundo, Costa Arenosa e Cavernas de Luminite).
  - Rios sinuosos, cavernas verticais, camadas profundas de xisto (`shale`), lagos subterrâneos de lava e filões de minérios (Carvão, Ferro, Ouro, Diamante e Luminite).
  - Estruturas geradas proceduralmente: Aldeias habitáveis com mobília e baús, Ruínas do Deserto e Minas Subterrâneas Abandonadas.
- **Segunda Dimensão — Reino Cristalino de Umbra:**
  - Ilhas flutuantes, espirais de obsidiana e luminite, flora bioluminescente e cidadelas guardadas pelo boss **Colosso de Cristal**.
- **Sistema Completo de 84 Blocos, Crafting e Fundição:**
  - Mais de 60 texturas pixel-art 16×16 geradas proceduralmente num `Texture2DArray` com oclusão ambiental por vértice (Vertex AO), sombreamento direcional, água/lava animadas e vegetação com movimento ao vento.
  -Mais de 55 receitas de fabrico (2×2 no inventário e 3×3 na Bancada de Trabalho + Livro de Receitas de 1 clique) e 21 receitas de fundição na Fornalha.
- **Sobrevivência, Agricultura, Pesca e Criaturas Voxel:**
  - Vida, Fome, Saturação, Oxigénio, dano de queda/lava/fogo, armaduras (Couro, Ferro, Ouro, Diamante) e ferramentas em 5 níveis.
  - Criaturas passivas, neutras e hostis com modelos 3D articulados e IA: Vacas, Ovelhas (tosquiáveis), Porcos, Galinhas, Lebres Árticas, Peixes, Lobos (domesticáveis com Osso), Zombies, Esqueletos Arqueiros, Aranhas, *Ember Stalkers* (explosivos), Espectros Voadores e o chefe **Colosso de Cristal**.
- **Multijogador ENet:**
  - Arquitetura cliente-servidor com autoridade do servidor, sincronização de jogadores e blocos em tempo real e chat com comandos.

## Como Executar

1. Abre a pasta `game/` no **Godot Engine 4.4+** ou executa:
   ```bash
   godot --path game
   ```
2. Para correr a suite de testes automatizados (headless):
   ```bash
   godot --headless --path game -- --self-test
   ```
