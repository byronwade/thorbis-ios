from pathlib import Path
import sys
root=Path(sys.argv[1]) / 'Thorbis/Sources'
def extract(file,name):
    text=(root/file).read_text(); start=text.index(name); brace=text.index('{',start); depth=0
    for i in range(brace,len(text)):
        if text[i]=='{': depth+=1
        if text[i]=='}':
            depth-=1
            if depth==0: return text[start:i+1]
    raise ValueError(name)
items=[]
for name in ['struct FieldMoney:', 'struct FieldEstimateLineSourceSnapshot:', 'struct FieldLineSource:', 'struct FieldLine:', 'struct FieldSignatureRecord:', 'struct FieldPhysicalServiceEvidence:', 'struct InvoiceRecord:']:
    items.append(extract('FieldAPI.swift',name))
for name in ['struct FieldInvoiceLinesRequest:', 'enum FieldInvoiceLineSourceInput:', 'struct FieldInvoiceLineInput:']:
    items.append(extract('FinancialActionAPI.swift',name))
items.append(extract('WorkspaceAPI.swift','struct PriceBookListItem:'))
(Path(sys.argv[2]) / 'models.swift').write_text('import Foundation\n'+'\n'.join(items))
