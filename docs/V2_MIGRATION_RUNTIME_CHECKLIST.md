# MZ Doors V2 — migração e ativação

O runtime V2 inicia desabilitado:

```lua
Config.V2.RuntimeEnabled = false
Config.V2.NativeDefinitionsDuringMigration = true
```

Isso permite criar as tabelas e revisar a migração sem substituir as portas
legadas. Portas novas criadas diretamente pelo painel já funcionam; definições
importadas do legado aguardam o corte completo para não serem registradas duas
vezes sobre o mesmo objeto físico.

## 1. Preparação

1. Faça backup externo do banco.
2. Garanta a ordem:

```cfg
ensure oxmysql
ensure ox_lib
ensure mz_core
ensure mz_menu
ensure mz_interact
ensure mz_doors
ensure mz_props
ensure mz_world_editor
ensure mz_admin
```

3. Reinicie:

```text
restart mz_core
restart mz_menu
restart mz_interact
restart mz_doors
restart mz_world_editor
restart mz_admin
```

O primeiro start cria `mz_door_definitions` e `mz_door_leaves`. A tabela `mz_world_doors` não é apagada.

## 2. Dry-run

No console ou com a permissão `staff.world.doors.manage`:

```text
/mzdoorsv2 dryrun
```

Revise:

- quantidade de linhas legadas;
- portas lógicas;
- simples;
- duplas;
- grupos com mais de duas folhas;
- registros já migrados;
- registros inválidos.

Não prossiga se houver registros inválidos sem revisão.

## 3. Migração

```text
/mzdoorsv2 migrate
```

A migração:

- é idempotente por `legacy_key`;
- preserva a tabela legada;
- transforma `double_group` em uma porta lógica;
- cria uma folha para cada objeto físico;
- preserva ACE legado como política `legacy_ace`;
- usa ponto explícito quando existir;
- calcula a média das folhas como fallback.

Execute novamente:

```text
/mzdoorsv2 dryrun
```

O número de grupos migrados deve corresponder ao total válido.

## 4. Validação antes do corte

Com runtime ainda desligado:

- abra `/admin`;
- entre em `Mundo e cenários`;
- confira `Portas cadastradas`;
- crie uma porta simples de teste;
- crie uma porta dupla de teste;
- valide label, code, folhas, interação e política.

Durante a seleção visual:

- centralize a folha no retículo;
- use `Q` para alternar entre folha, vidro, moldura e outros objetos sobrepostos;
- use `E` para confirmar;
- use `BACKSPACE` para cancelar;
- em portas duplas, a folha `1/2` fica excluída do seletor durante a etapa `2/2`;
- duas folhas do mesmo modelo são aceitas quando possuem posições diferentes;
- confira modelo, distância, heading e coordenadas no painel;
- nenhuma linha, caixa ou seta azul deve ser desenhada.

Com o corte completo desligado:

- portas novas do painel controlam o Door System e podem ser testadas normalmente;
- definições importadas por `legacy_key` continuam inativas no V2;
- as portas da tabela legada continuam sendo controladas pelo runtime legado.

## 5. Ativação

Altere:

```lua
Config.V2.RuntimeEnabled = true
```

Depois:

```text
restart mz_doors
restart mz_admin
```

Com V2 ativo:

- o runtime legado entrega snapshot vazio;
- o V2 registra as folhas físicas;
- existe um único ponto `mz_interact` por porta lógica;
- `E` tranca/destranca;
- `G` bate e o som é enviado aos jogadores próximos;
- auto-lock usa revisão para cancelar timers antigos.

## 6. Checklist runtime

- [ ] Porta simples aparece uma vez.
- [ ] Porta dupla possui um marker.
- [ ] As duas folhas mudam juntas.
- [ ] Marker está no centro esperado.
- [ ] Texto contextual aparece em duas linhas e com fundo legível.
- [ ] Não aparece objeto/marker geométrico azul.
- [ ] Não existe blip no mapa.
- [ ] Apenas o ponto mais próximo responde.
- [ ] Acesso público funciona.
- [ ] Acesso Staff funciona.
- [ ] O criador lista somente organizações ativas do `mz_core`; não existe digitação manual do código.
- [ ] O servidor rejeita organização inexistente/inativa e salva o código canônico.
- [ ] Organização e nível mínimo funcionam.
- [ ] Jogador membro de `police` passa por `HasGradeOrAbove(source, "police", nível)`.
- [ ] Acesso negado mostra apenas “A porta está trancada”, sem mencionar permissões.
- [ ] `mz_notify` é usado quando iniciado e `mz_menu` assume como fallback.
- [ ] Capability organizacional falha fechada.
- [ ] Staff com `staff.world.doors.manage` possui override.
- [ ] `G` reproduz batida apenas em clients próximos.
- [ ] Auto-lock não executa timer antigo.
- [ ] Reconnect recebe o estado correto.
- [ ] Reload não deixa Door System antigo.
- [ ] Lock/unlock pelo painel atualiza todos os clients.
- [ ] Arquivar remove folhas e marcação sem apagar o registro.
- [ ] Restaurar registra novamente folhas e marcação.
- [ ] Lista e detalhes respeitam `staff.world.view`.
- [ ] Gestão e arquivo respeitam permissões separadas.

## 7. Retorno temporário

Se o runtime V2 apresentar problema:

1. altere `Config.V2.RuntimeEnabled = false`;
2. reinicie `mz_doors`;
3. o runtime volta a ler `mz_world_doors`.

Não apague as tabelas V2. Corrija e repita o checklist antes de reativar.
