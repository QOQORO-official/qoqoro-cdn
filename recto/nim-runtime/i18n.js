/* Shared UI-only localization. Canonical copy: qnote-nim-wasm/public/wasm.
 * Never translate canvas content, PDF text, file names, editable values or IDs. */
(() => {
  'use strict';
  if (globalThis.QNoteI18n) return;
  const ja = {
    'File':'ファイル','Main':'ホーム','Objects':'オブジェクト','Tables':'表','Layout':'レイアウト','Misc':'その他',
    'Open':'開く','Save':'保存','Print':'印刷','Theme':'テーマ','Theme settings':'テーマ設定',
    'Buttons':'ボタン','Theme Color':'テーマの色','Background':'背景','Language':'言語',
    'Automatic (system language)':'自動（システムの言語）','Appearance':'外観','Use system setting':'システム設定を使用',
    'Light':'ライト','Dark':'ダーク','Custom colors':'カスタムカラー','Accent color':'アクセントカラー',
    'Custom surface color':'背景色','Custom text color':'文字色','Preview':'プレビュー','Reset colors':'色をリセット',
    'Toolbar size':'ツールバーのサイズ','Extra compact':'最小','Compact':'コンパクト','Comfortable':'標準','Large':'大',
    'Find a button':'ボタンを検索','Upload logo':'ロゴをアップロード','Restore default':'既定に戻す','Reset buttons':'ボタンをリセット',
    'Default logo restored':'既定のロゴに戻しました','Logo ready. Apply to save.':'ロゴを読み込みました。「適用」で保存します。',
    'Choose a logo under 512 KB.':'512 KB以下のロゴを選択してください。','Choose a PNG, SVG or JPG file.':'PNG、SVG、JPGファイルを選択してください。',
    'Could not read this logo.':'ロゴを読み込めませんでした。','Could not load this logo.':'ロゴを読み込めませんでした。',
    'Upload a PNG, SVG or JPG logo (up to 512 KB per button). Buttons with logos display the logo and show their name in a tooltip.':'PNG、SVG、JPGのロゴをアップロードできます（ボタンごとに512 KBまで）。ロゴのあるボタンはアイコンを表示し、名前はツールチップに表示します。',
    'Accent colors apply to active tabs and controls. Custom surface and text colors apply when Custom colors is selected.':'アクセントカラーは選択中のタブやコントロールに適用されます。背景色と文字色は「カスタムカラー」を選択した場合に適用されます。',
    'Apply':'適用','Cancel':'キャンセル','Close':'閉じる','Done':'完了','Reset':'リセット','Delete':'削除','Remove':'削除','Insert':'挿入','Add':'追加','Edit':'編集',
    'Find':'検索','Pages':'ページ','Outline':'見出し','Navigation':'ナビゲーション','Headings':'見出し','Results':'検索結果',
    'Search document':'文書内を検索','Search document…':'文書内を検索…','Search text…':'テキストを検索…','Replace':'置換','Replace all':'すべて置換',
    'Previous':'前へ','Next':'次へ','Previous page':'前のページ','Next page':'次のページ','Find (Ctrl+F)':'検索 (Ctrl+F)','Browse document pages':'ページを参照',
    'Table of Contents':'目次','Contents':'目次','No results':'一致する結果がありません','No results found':'一致する結果がありません',
    'Undo':'元に戻す','Redo':'やり直す','Undo (Ctrl+Z)':'元に戻す (Ctrl+Z)','Redo (Ctrl+Y)':'やり直す (Ctrl+Y)',
    'Copy':'コピー','Cut':'切り取り','Paste':'貼り付け','Select all':'すべて選択','Bold':'太字','Italic':'斜体','Underline':'下線','Strikethrough':'取り消し線',
    'Font':'フォント','Font size':'フォントサイズ','Text color':'文字色','Highlight':'蛍光ペン','Align left':'左揃え','Align center':'中央揃え','Align right':'右揃え','Justify':'両端揃え',
    'Paragraph':'段落','Line spacing':'行間','Bullets':'箇条書き','Numbering':'段落番号','Indent':'インデント','Increase indent':'インデントを増やす','Decrease indent':'インデントを減らす',
    'Superscript':'上付き文字','Subscript':'下付き文字','Clear formatting':'書式をクリア','Normal':'標準','Heading 1':'見出し 1','Heading 2':'見出し 2','Heading 3':'見出し 3',
    'Insert Math':'数式を挿入','Math':'数式','Equation':'数式','Link':'リンク','Image':'画像','Text Box':'テキストボックス','Text box':'テキストボックス','Doodle':'手描き',
    'Table':'表','Insert table':'表を挿入','Rows':'行','Columns':'列','Width':'幅','Height':'高さ','Border':'罫線','Borders':'罫線','Cell':'セル','Merge cells':'セルを結合','Split cells':'セルを分割',
    'Page setup':'ページ設定','Page size':'用紙サイズ','Orientation':'印刷の向き','Portrait':'縦','Landscape':'横','Margins':'余白','Top':'上','Bottom':'下','Left':'左','Right':'右',
    'Header':'ヘッダー','Footer':'フッター','Page number':'ページ番号','Page break':'改ページ','Section break':'セクション区切り',
    'Objects & Elements':'オブジェクトと要素','All pages':'すべてのページ','Search objects...':'オブジェクトを検索…',
    'Above text · front to back':'前面 · 手前から奥へ','Behind text · front to back':'背面 · 手前から奥へ','Document flow · text, tables & inline objects':'本文 · テキスト、表、行内オブジェクト',
    'Bring to front':'最前面へ移動','Send to back':'最背面へ移動','Bring forward':'前面へ移動','Send backward':'背面へ移動',
    'Crop image':'画像をトリミング','Opacity':'不透明度','Color':'色','Solid color':'単色','Background image':'背景画像','Upload image':'画像をアップロード',
    'No vault note selected':'文書が選択されていません','Vault & Admin':'保管庫と管理','VAULT':'保管庫','Vault':'保管庫','Vault root':'保管庫のルート',
    'Refresh':'更新','Sign out':'サインアウト','Sign in':'サインイン','Username':'ユーザー名','Password':'パスワード','Save password':'パスワードを保存',
    'Create your admin account':'管理者アカウントを作成','Create account':'アカウントを作成',
    'First launch: choose a password of at least 12 characters. No default password is created.':'初回起動です。12文字以上のパスワードを設定してください。既定のパスワードはありません。',
    'Cannot connect to the vault server.':'保管庫サーバーに接続できません。','Incorrect username or password':'ユーザー名またはパスワードが正しくありません',
    'Too many attempts. Wait 30 seconds.':'試行回数が多すぎます。30秒お待ちください。','Current password is incorrect':'現在のパスワードが正しくありません',
    'Enter a username and a password of at least 12 characters':'ユーザー名と12文字以上のパスワードを入力してください',
    'Search notes…':'文書を検索…','Search notes':'文書を検索','Loading vault…':'保管庫を読み込み中…','PDF Viewer':'PDFビューアー',
    'Upload QNote / PDF':'QNote / PDFをアップロード','Upload files':'ファイルをアップロード','New folder':'新しいフォルダー','New note':'新しい文書','Rename':'名前を変更',
    'Move':'移動','Delete account, credentials and all vault files':'アカウント、認証情報、保管庫内の全ファイルを削除',
    '← Back to workspace':'← ワークスペースに戻る','Vault folder':'保管庫フォルダー','Local folder path':'ローカルフォルダーのパス',
    'Choose an existing folder. Switching vault never moves or copies your documents. QNote and PDF files are indexed automatically.':'既存のフォルダーを選択してください。保管庫を切り替えても文書は移動・コピーされません。QNoteとPDFファイルは自動的に登録されます。',
    'Admin account':'管理者アカウント','Admin username':'管理者のユーザー名','New password (leave blank to keep it)':'新しいパスワード（変更しない場合は空欄）',
    'Current password (required to apply settings)':'現在のパスワード（設定の適用に必要）','Apply settings & sign out':'設定を適用してサインアウト','Local server':'ローカルサーバー',
    'Enter your current password above before resetting.':'リセットする前に、上の欄に現在のパスワードを入力してください。',
    'Type DELETE ALL to confirm permanent deletion':'完全に削除するには DELETE ALL と入力してください',
    'Apply settings and sign in again? Switching vault does not move or copy any documents.':'設定を適用して再度サインインしますか？ 保管庫を切り替えても文書は移動・コピーされません。',
    'Word documents':'Word文書','Import DOCX':'DOCXをインポート','Export DOCX':'DOCXをエクスポート',
    'Import a DOCX as a new QNote, or export the current editor document. Some Word-specific content may need adjustment after conversion.':'DOCXを新しいQNoteとして取り込むか、編集中の文書をエクスポートします。Word固有の内容は変換後に調整が必要な場合があります。',
    'The editor is still loading':'エディターを読み込み中です','Choose PDF':'PDFを選択','Load sample':'サンプルを開く',
    'Zoom out':'縮小','Zoom in':'拡大','Fit':'全体を表示','Filter…':'絞り込み…','Open a PDF to see its outline.':'PDFを開くと目次が表示されます。',
    'Annotate (draw on pages)':'注釈（ページに描画）','Pen':'ペン','Highlighter':'蛍光ペン','Stroke eraser':'ストローク消しゴム','Custom color':'カスタムカラー','Done annotating':'注釈を終了',
    'Copy text':'テキストをコピー','Copy and cite':'コピーして引用','Copy & cite':'コピーして引用','Copy citation':'引用をコピー','Area bookmark':'領域ブックマーク','Bookmarks':'ブックマーク',
    'Virtual scroll':'仮想スクロール','On-demand render':'必要なページを描画',
    'A virtualized PDF viewer engineered for documents of any length. Smooth scroll, instant zoom, paged on demand.':'長い文書も快適に閲覧できるPDFビューアー。滑らかなスクロールと高速ズームで、必要なページを表示します。'
  };
  Object.assign(ja, {
    'Custom':'カスタム','Custom List':'カスタムリスト','Custom List…':'カスタムリスト…','Restart at':'開始番号：',
    'Adjust List Indents…':'リストのインデントを調整…','Set Adjust Indents':'リストのインデントを調整',
    'Continue Numbering':'番号を継続','Set List Value…':'リストの値を設定…','Set List Value':'リストの値を設定',
    'Start new list':'新しいリストを開始','Continue from previous list':'前のリストから継続',
    'Advance value (skip numbers)':'値を進める（番号をスキップ）','Set value to':'開始する値',
    'Number position (cm)':'番号の位置（cm）','Text indent (cm)':'文字のインデント（cm）',
    'Follow number with':'番号に続く文字','Tab character':'タブ文字','Space':'スペース','Nothing':'なし',
    'Add tab stop at':'タブ位置を追加','Tab stop (cm)':'タブ位置（cm）','OK':'OK',
    'Applies to this level in the current list.':'現在のリストの同じレベルに適用します。',
    'Normal text':'標準のテキスト','Title':'タイトル','Heading style':'見出しスタイル','List style':'リストのスタイル','No List':'リストなし','• Bullet':'• 箇条書き','— Dash':'— ダッシュ',
    'Promote list level':'リストのレベルを上げる','Demote list level':'リストのレベルを下げる','Define numbering format':'段落番号の書式設定','Numbering ▾':'段落番号 ▾','Spacing ▾':'間隔 ▾',
    'Line and paragraph spacing':'行と段落の間隔','Font family':'フォント','Decrease font size':'フォントサイズを小さくする','Increase font size':'フォントサイズを大きくする','Font size in points':'フォントサイズ（ポイント）',
    'Page Break':'改ページ','Insert or edit link (Ctrl+K)':'リンクの挿入・編集 (Ctrl+K)','Print document (Ctrl+P)':'文書を印刷 (Ctrl+P)','Objects and Selection Pane':'オブジェクトと選択ウィンドウ',
    'Object wrapping mode':'文字列の折り返し','Wrap: Inline':'折り返し：行内','Wrap: Square':'折り返し：四角形','Wrap: Top & Bottom':'折り返し：上下','Wrap: In Front of Text':'折り返し：前面','Wrap: Behind Text':'折り返し：背面','Wrap: Through Text':'折り返し：内部',
    'Move with text':'文字列と一緒に移動','Keep this floating object attached to its text anchor':'このオブジェクトをテキストのアンカーに固定',
    'Properties ▾':'プロパティ ▾','Object properties':'オブジェクトのプロパティ','Object appearance and spacing':'オブジェクトの外観と間隔','No border':'罫線なし','Radius':'角の丸み','Corner radius in pixels':'角の半径（ピクセル）',
    'Textbox or image border color':'テキストボックス・画像の枠線色','Textbox or image background color':'テキストボックス・画像の背景色','Auto-fit text':'テキストに合わせる','Fill':'塗りつぶし','No fill':'塗りつぶしなし',
    'Inner content margins (px)':'内側の余白（px）','Wrap margins (px)':'折り返しの余白（px）','Link all four':'四辺を連動',
    '▦ Insert Table':'▦ 表を挿入','＋ Row':'＋ 行','− Row':'− 行','＋ Column':'＋ 列','− Column':'− 列','Merge':'結合','Split':'分割',
    'Page layout':'ページレイアウト','Ruler':'ルーラー','Show or hide ruler (Ctrl+R)':'ルーラーの表示・非表示 (Ctrl+R)','Page margins':'ページの余白','Page margins (px)':'ページの余白（px）','Header & Footer':'ヘッダーとフッター',
    'Template':'テンプレート','Reveal ID':'IDを表示','Drawing Mode':'描画モード','Crop':'トリミング','Image URL':'画像のURL','New Program':'新しいプログラム','Custom Field':'カスタムフィールド','Emoji':'絵文字','Settings':'設定',
    'Copy relative path':'相対パスをコピー','Path copied':'パスをコピーしました','Expand / collapse':'展開・折りたたみ','Collapse all folders':'すべてのフォルダーを折りたたむ','Duplicate':'複製','Download copy':'コピーをダウンロード','Rename / move':'名前の変更・移動','Move to Trash':'ゴミ箱に移動',
    'New note name':'新しい文書の名前','New folder name':'新しいフォルダーの名前','Duplicate note as':'複製する文書の名前','New vault-relative path':'保管庫を基準とした新しい相対パス',
    'Resize sidebar':'サイドバーの幅を変更','QNote editor':'QNoteエディター','Switch app':'アプリを切り替え','New QNote':'新しいQNote','Upload QNote/PDF':'QNote / PDFをアップロード',
    'Import Word (.docx)':'Wordをインポート (.docx)','Export Word (.docx)':'Wordをエクスポート (.docx)',
    'Starts with the desktop app and stops when its window closes. Settings: %LOCALAPPDATA%\\QNoteVault. Previous saves: Backups; deleted notes: Trash.':'デスクトップアプリと同時に起動し、ウィンドウを閉じると停止します。設定：%LOCALAPPDATA%\\QNoteVault。以前の保存内容：Backups、削除した文書：Trash。',
    'Only stylus and mouse draw — fingers scroll and pinch':'ペンとマウスで描画、指でスクロールと拡大・縮小','stylus-only':'ペンのみ',
    'Copy & Cite':'コピーして引用','Copy Text':'テキストをコピー','Highlight text':'テキストに蛍光ペン','Add bookmark':'ブックマークを追加','Delete bookmark':'ブックマークを削除',
    'Copy and Cite':'コピーして引用','Copy Bookmark Link':'ブックマークのリンクをコピー','Delete Highlight':'蛍光ペンを削除','Copy Image':'画像をコピー','Delete Area':'領域を削除','Save Bookmark':'ブックマークを保存','Discard':'破棄','Add Bookmark Area':'ブックマーク領域を追加','Search Google':'Googleで検索',
    'Yellow':'黄色','Pink':'ピンク','Purple':'紫','Green':'緑','Copied!':'コピーしました！','Copied with citation!':'引用リンク付きでコピーしました！',
    'Switch to previous app':'前のアプリに切り替え','Close Navigation':'ナビゲーションを閉じる','Document navigation':'文書のナビゲーション','Search headings':'見出しを検索','Search headings…':'見出しを検索…',
    'Objects and Elements':'オブジェクトと要素','Close Selection Pane':'選択ウィンドウを閉じる','Filter objects by page':'ページでオブジェクトを絞り込む','Search objects…':'オブジェクトを検索…','Search objects':'オブジェクトを検索',
    'Display':'表示','One workspace image':'ワークスペース全体の画像','Left and right images':'左右の画像','Left image':'左側の画像','Right image':'右側の画像',
    'Image blur':'画像のぼかし','Left image blur':'左側の画像のぼかし','Right image blur':'右側の画像のぼかし','Left width (px)':'左側の幅（px）','Right width (px)':'右側の幅（px）','Remove background':'背景を削除',
    'Workspace decoration only: backgrounds do not change document layout and are not printed. Images are saved in this browser.':'ワークスペースの背景設定です。文書のレイアウトや印刷には影響しません。画像はこのブラウザーに保存されます。',
    'Choose a PNG, JPG, WebP or GIF image under 8 MB.':'8 MB以下のPNG、JPG、WebP、GIF画像を選択してください。','Could not read image':'画像を読み込めませんでした',
    'Browser storage is full. Use smaller logos or background images, or remove existing custom images.':'ブラウザーの保存容量が不足しています。ロゴや背景画像を小さくするか、登録済みの画像を削除してください。',
    'Spacing (centimeters)':'間隔（cm）','Line between columns':'段の間に線を表示','Apply to all pages':'すべてのページに適用','+ Add page':'+ ページを追加','Applies to: This document':'適用先：この文書','Paper size':'用紙サイズ','Page color':'ページの色',
    'Page width (centimeters)':'ページの幅（cm）','Margins (centimeters)':'余白（cm）','Infinite Blog':'無限スクロール','Enter valid dimensions.':'有効な寸法を入力してください。','Add at least one valid page number.':'有効なページ番号を1つ以上追加してください。',
    'Infinite Blog uses one continuous column. Switch to Pages in Page layout to use multiple columns.':'無限スクロールでは1段の連続したレイアウトを使用します。段組みを使うには、ページレイアウトで「ページ」に切り替えてください。',
    'Listed physical pages use these columns; other pages use one column. Content reflows as page settings change.':'指定したページに段組みを適用し、他のページは1段で表示します。ページ設定の変更に合わせて内容が再配置されます。',
    'Center':'中央','Insert into the last edited zone:':'最後に編集した領域に挿入：','Page X of Y':'総ページ数付きのページ番号',"Today's date":'今日の日付','Different first page':'先頭ページのみ別指定','First page header':'先頭ページのヘッダー','First page footer':'先頭ページのフッター',
    'Page numbers':'ページ番号','Number format':'番号の書式','Start at':'開始番号','Text':'テキスト','Size (pt)':'サイズ（pt）','Separator line':'区切り線','Header from top edge (cm)':'上端からヘッダーまで（cm）','Footer from bottom edge (cm)':'下端からフッターまで（cm）','Remove all':'すべて削除',
    'Keep header and footer distances within half the page height.':'ヘッダーとフッターの距離は、ページの高さの半分以内にしてください。',
    'Automatic Table 1':'自動作成の目次 1','Automatic Table 2':'自動作成の目次 2','Custom Table of Contents…':'ユーザー設定の目次…','Choose the title, heading levels and page numbers':'タイトル、見出しのレベル、ページ番号を設定',
    'Show levels':'表示するレベル','Headings 1–2':'見出し 1–2','Headings 1–3':'見出し 1–3','Show page numbers':'ページ番号を表示','Include Title paragraphs':'タイトルの段落を含める','Update Table':'目次を更新','Re-read headings and page numbers into the existing table':'見出しとページ番号を再取得して目次を更新','Remove Table of Contents':'目次を削除','Delete the table; headings are not changed':'見出しを変更せずに目次を削除',
    'A table of contents needs pages. Switch Page layout from Infinite Blog to Pages first.':'目次にはページが必要です。ページレイアウトを「無限スクロール」から「ページ」に切り替えてください。',
    'This document already has a table of contents. Update it after editing headings, or remove it to insert a different style.':'この文書には目次があります。見出しを編集したら更新してください。別のスタイルを挿入するには、既存の目次を削除してください。',
    'Pagination is still catching up; page numbers are refreshed automatically once it settles.':'ページを計算中です。完了するとページ番号が自動的に更新されます。'
  });
  const reverse = new Map(Object.entries(ja).map(([en, jp]) => [jp, en]));
  const records = new WeakMap();
  let language = 'en';
  const stored = () => { try { return JSON.parse(localStorage.getItem('qnote-theme') || '{}').language || 'auto'; } catch { return 'auto'; } };
  const resolve = preference => preference === 'ja' || preference === 'en' ? preference :
    (/^ja(?:-|$)/i.test(navigator.languages?.[0] || navigator.language || '') ? 'ja' : 'en');
  const english = value => reverse.get(value) || value;
  const t = value => language === 'ja' ? (ja[value] || value) : value;
  // Native dialogs use the same catalog; entered values are never translated.
  for (const name of ['alert','confirm','prompt']) {
    const native = window[name].bind(window);
    window[name] = (message,...args) => native(t(String(message)),...args);
  }
  // Explicit chrome boundaries. A document's headings, snippets, filenames and
  // editable controls may happen to equal a dictionary key: leave them alone.
  const scope = '#qnote-object-menu,#toolbar-container,#tab-strip,#selection-pane,.qnote-dialog,.toolbar-popup,#qnote-navigation,#qnote-misc-dialog,#qnote-misc-tooltip,#qnote-crop-tools,.vault-header,.sidebar-title-row,.sidebar-status,.iframe-nav,#vaultRoot,#fileSearch,#context,body[data-vault-page] main,dialog,.toolbar,.outline-header,.outline-search,.annot-bar,#welcome,#ctx-menu,#toast';
  const skip = '[data-i18n-skip],[contenteditable],textarea,script,style,svg,canvas,math,.katex,.MathJax,#qnote-nav-content,#outline-pane-list,#sel-pane-list,#fileList,#currentNote,.workspace-name,#filename,#outline-body,.textLayer,#pages,#template-designer';
  function eligible(element) { return element && !element.closest(skip) && !!element.closest(scope); }
  function translate(node, key, value, write) {
    let record = records.get(node); if (!record) records.set(node, record = {});
    let entry = record[key];
    if (!entry || value !== entry.output) entry = record[key] = {source:value};
    const trimmed = entry.source.trim();
    const output = entry.source.replace(trimmed, t(trimmed));
    entry.output = output;
    if (value !== output) write(output);
  }
  function visit(node) {
    if (node.nodeType === 3) {
      if (eligible(node.parentElement)) translate(node, 'text', node.data, value => node.data = value);
      return;
    }
    if (node.nodeType !== 1 || node.matches(skip)) return;
    if (eligible(node)) for (const key of ['title','aria-label','placeholder','data-tip']) {
      if (node.hasAttribute(key)) translate(node, key, node.getAttribute(key), value => node.setAttribute(key,value));
    }
    for (const child of node.childNodes) visit(child);
  }
  function apply(preference = stored()) {
    language = resolve(preference);
    document.documentElement.lang = language;
    // Only walk UI roots on a switch, never the editor's rendered document.
    for (const root of document.querySelectorAll(scope)) if (!root.parentElement?.closest(scope)) visit(root);
    window.dispatchEvent(new CustomEvent('qnote-language-changed',{detail:{language,preference}}));
  }
  globalThis.QNoteI18n = {t, english, apply, get language() { return language; }, preference:stored};
  language = resolve(stored());
  document.documentElement.lang = language;
  function start() {
    apply();
    new MutationObserver(changes => {
      for (const change of changes) {
        if (change.type === 'childList') for (const node of change.addedNodes) visit(node);
        else if (change.type === 'characterData') visit(change.target);
        else if (eligible(change.target)) {
          const key=change.attributeName, value=change.target.getAttribute(key);
          if(value!==null) translate(change.target,key,value,result=>change.target.setAttribute(key,result));
        }
      }
    }).observe(document.body,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['title','aria-label','placeholder','data-tip']});
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded',start,{once:true}); else start();
  window.addEventListener('storage',event=>{if(event.key==='qnote-theme'||event.key===null)apply();});
  window.addEventListener('languagechange',()=>{if(stored()==='auto')apply();});
})();
